#!/usr/bin/env bash
# GitHub Actions self-hosted runner の PATH ガード
#
# 出所: https://github.com/ousiassllc/actions-runner-setup-base （vendored copy）
#       上流を更新したらこのファイルも追従させる。
#
# 背景:
#   runner の systemd サービス（ExecStart=runsvc.sh）は、起動時に <runner dir>/.path があれば
#   `export PATH=$(cat .path)` で PATH を丸ごと上書きする。.env の PATH= より後に効くので、
#   .path が PATH の正になる。
#   .path は config.sh / svc.sh install を実行したシェルの PATH が一度だけ書かれる。fish の
#   ログイン中に実行すると fnm の一時パス（/run/user/<uid>/fnm_multishells/...）が記録され、
#   再起動やログアウトで消えると node / npx が見えなくなる（ジョブが exit 127 で落ちる）。
#
# このファイルの役割（3 通りの使い方で、安定 PATH の定義と判定を 1 箇所に持つ）:
#   1. runner-host-setup.sh が source して、安定 PATH の定義と .path の修復関数を使う
#   2. Linux: runner-host-setup.sh が <runner dir>/path-guard.sh として設置し、systemd drop-in の
#      ExecStartPre= から起動のたびに実行される
#        path-guard.sh <runner dir> <home>
#   3. macOS: 同じく設置した path-guard.sh を、launchd の plist の ProgramArguments から
#      起動のたびに実行する（launchd に ExecStartPre 相当が無いため。修復後に runsvc.sh へ exec する）
#        path-guard.sh --exec <runner dir> <home>
#
# 起動時の動き:
#   .path を検査し、次のどれかに当たれば安定 PATH へ書き直す。
#     - fnm_multishells を含む
#     - <home>/.local/share/fnm/aliases/default/bin を含まない
#     - その PATH で node / npx が引けない
#   書き直す前に .path.bak-<日時> を残し、修復内容は標準出力へ出す
#   （systemd の journal に入る: journalctl -u <unit> / macOS は <home>/Library/Logs/<label>/stdout.log）。
#   正常な .path は書き換えない。
#   修復しても node が見つからない（fnm default 未設定など）ときはエラーを出すが、
#   runner の起動は止めない（ExecStartPre は常に成功を返す。--exec も runsvc.sh へ進む）。

# fnm の aliases/default/bin（node の更新に追従するシンボリックリンク）の置き場所を 1 行 1 パスで出す。
# Linux は ~/.local/share/fnm。macOS は、このリポジトリの fnm.sh が使う公式インストーラの既定が
# ~/Library/Application Support/fnm（XDG_DATA_HOME 未設定のとき）なので、それと ~/.local/share/fnm の両方を許す。
runner_fnm_default_bin_dirs() {
	local home=$1
	if [ "$(uname -s)" = Darwin ]; then
		printf '%s\n' "$home/Library/Application Support/fnm/aliases/default/bin"
	fi
	printf '%s\n' "$home/.local/share/fnm/aliases/default/bin"
}

# 安定 PATH。ログイン時の一時パス（fnm_multishells）を含めない。
# fnm の aliases/default は node の更新に追従するシンボリックリンクなので、バージョンを固定せずに済む。
# OS（uname -s）で分ける。macOS は Homebrew（Apple Silicon の /opt/homebrew）を入れ、
# /opt/nvim/bin・/usr/games・/snap/bin など Linux だけのものを外す。
runner_stable_path() {
	local home=$1
	case "$(uname -s)" in
	Darwin)
		printf '%s' "$home/Library/Application Support/fnm/aliases/default/bin:$home/.local/share/fnm/aliases/default/bin:/opt/homebrew/bin:/opt/homebrew/sbin:/usr/local/go/bin:$home/go/bin:$home/.cargo/bin:$home/.bun/bin:$home/.local/bin:$home/Library/Application Support/fnm:$home/.local/share/fnm:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
		;;
	*)
		printf '%s' "$home/.local/share/fnm/aliases/default/bin:/opt/nvim/bin:/usr/local/go/bin:$home/go/bin:$home/.cargo/bin:$home/.bun/bin:$home/.local/bin:$home/.local/share/fnm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
		;;
	esac
}

# ジョブ shell 相当（非ログイン・最小環境）で、指定の PATH だけを頼りに node / npx が引けるか。
runner_path_has_node() {
	local home=$1 path=$2
	env -i HOME="$home" PATH="$path" "$BASH" --noprofile --norc -c 'command -v node npx' >/dev/null 2>&1
}

# .path に修復が必要なら理由を出力して 0 を返す。正常なら何も出さず 1 を返す。
runner_path_file_problem() {
	local file=$1 home=$2 current fnm_dirs dir found
	if [ ! -f "$file" ]; then
		echo "$file が無い"
		return 0
	fi
	# runsvc.sh は `cat .path` で読む。末尾の改行は影響しない。
	current=$(<"$file")
	case "$current" in
	*fnm_multishells*)
		echo "fnm の一時パス（fnm_multishells）を含む"
		return 0
		;;
	esac
	fnm_dirs=$(runner_fnm_default_bin_dirs "$home")
	found=0
	while IFS= read -r dir; do
		case ":$current:" in
		*":$dir:"*) found=1 ;;
		esac
	done <<<"$fnm_dirs"
	if [ "$found" -ne 1 ]; then
		echo "${fnm_dirs//$'\n'/ / } を含まない"
		return 0
	fi
	if ! runner_path_has_node "$home" "$current"; then
		echo "その PATH で node / npx が引けない"
		return 0
	fi
	return 1
}

# .path が外れていれば安定 PATH に書き直す。
# 戻り値: 0 = 書き直した / 1 = 触らなかった / 2 = 書き込みに失敗した
runner_repair_path_file() {
	local file=$1 home=$2 reason stable bak tmp rc=1
	if reason=$(runner_path_file_problem "$file" "$home"); then
		stable=$(runner_stable_path "$home")
		if [ -f "$file" ] && [ "$(<"$file")" = "$stable" ]; then
			# 既に安定 PATH なので書き直しても変わらない。node 側の問題（下で報告する）。
			echo "path-guard: $file は安定 PATH のまま（${reason}）"
		else
			echo "path-guard: $file を安定 PATH に修復する（${reason}）"
			if [ -f "$file" ]; then
				bak="$file.bak-$(date +%Y%m%d-%H%M%S)"
				cp -p -- "$file" "$bak" || {
					echo "path-guard: バックアップに失敗: $bak" >&2
					return 2
				}
				echo "path-guard: 退避した: $bak"
			fi
			# 同じディレクトリで一時ファイルを作って mv する。.path 自体が root 所有でも
			# ディレクトリの所有者なら置き換えられる。
			if tmp=$(mktemp "$file.XXXXXX") &&
				printf '%s\n' "$stable" >"$tmp" &&
				chmod 644 "$tmp" &&
				mv -f -- "$tmp" "$file"; then
				rc=0
			else
				echo "path-guard: $file の書き込みに失敗" >&2
				return 2
			fi
		fi
		if ! runner_path_has_node "$home" "$stable"; then
			echo "path-guard: NG: 安定 PATH でも node / npx が見えません（fnm で node を入れ、fnm default を設定してください）" >&2
		fi
	fi
	return "$rc"
}

# systemd の ExecStartPre から呼ばれる入口（macOS は下の --exec 経由）。runner の起動を止めないため、常に 0 を返す。
runner_path_guard_main() {
	local runner_dir=${1:-} home=${2:-}
	if [ -z "$runner_dir" ] || [ -z "$home" ]; then
		echo "path-guard: 使い方: $0 <runner dir> <home>" >&2
		return 0
	fi
	runner_repair_path_file "$runner_dir/.path" "$home" || true
	return 0
}

# launchd（macOS）の ProgramArguments から呼ばれる入口。systemd の ExecStartPre= に相当する。
# .path を検査・修復してから、runner dir の runsvc.sh へ exec する。
# runsvc.sh は launchd 直下のプロセスとして残る（シグナルもそのまま届く）。
# 引数が足りない、または runsvc.sh へ移れないときだけ失敗を返す（修復の失敗では止めない）。
runner_path_guard_exec() {
	local runner_dir=${1:-} home=${2:-}
	if [ -z "$runner_dir" ] || [ -z "$home" ]; then
		echo "path-guard: 使い方: $0 --exec <runner dir> <home>" >&2
		return 1
	fi
	runner_path_guard_main "$runner_dir" "$home"
	cd "$runner_dir" || return 1
	exec ./runsvc.sh
}

# 直接実行されたときだけ入口を呼ぶ（source されたときは関数定義だけ）。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	if [ "${1:-}" = "--exec" ]; then
		shift
		runner_path_guard_exec "$@"
		exit 1
	fi
	runner_path_guard_main "$@"
	exit 0
fi
