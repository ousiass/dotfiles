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
# このファイルの役割（2 通りの使い方で、安定 PATH の定義と判定を 1 箇所に持つ）:
#   1. runner-host-setup.sh が source して、安定 PATH の定義と .path の修復関数を使う
#   2. runner-host-setup.sh が <runner dir>/path-guard.sh として設置し、systemd drop-in の
#      ExecStartPre= から起動のたびに実行される
#        path-guard.sh <runner dir> <home>
#
# 起動時の動き:
#   .path を検査し、次のどれかに当たれば安定 PATH へ書き直す。
#     - fnm_multishells を含む
#     - <home>/.local/share/fnm/aliases/default/bin を含まない
#     - その PATH で node / npx が引けない
#   書き直す前に .path.bak-<日時> を残し、修復内容は標準出力へ出す
#   （systemd の journal に入る: journalctl -u <unit>）。
#   正常な .path は書き換えない。
#   修復しても node が見つからない（fnm default 未設定など）ときはエラーを出すが、
#   ExecStartPre は常に成功を返し、runner の起動は止めない。

# 安定 PATH。ログイン時の一時パス（fnm_multishells）を含めない。
# fnm の aliases/default は node の更新に追従するシンボリックリンクなので、バージョンを固定せずに済む。
runner_stable_path() {
	local home=$1
	printf '%s' "$home/.local/share/fnm/aliases/default/bin:/opt/nvim/bin:/usr/local/go/bin:$home/go/bin:$home/.cargo/bin:$home/.bun/bin:$home/.local/bin:$home/.local/share/fnm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin"
}

# ジョブ shell 相当（非ログイン・最小環境）で、指定の PATH だけを頼りに node / npx が引けるか。
runner_path_has_node() {
	local home=$1 path=$2
	env -i HOME="$home" PATH="$path" "$BASH" --noprofile --norc -c 'command -v node npx' >/dev/null 2>&1
}

# .path に修復が必要なら理由を出力して 0 を返す。正常なら何も出さず 1 を返す。
runner_path_file_problem() {
	local file=$1 home=$2 current
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
	case ":$current:" in
	*":$home/.local/share/fnm/aliases/default/bin:"*) ;;
	*)
		echo "$home/.local/share/fnm/aliases/default/bin を含まない"
		return 0
		;;
	esac
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
			echo "path-guard: $file は安定 PATH のまま（$reason）"
		else
			echo "path-guard: $file を安定 PATH に修復する（$reason）"
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

# systemd の ExecStartPre から呼ばれる入口。runner の起動を止めないため、常に 0 を返す。
runner_path_guard_main() {
	local runner_dir=${1:-} home=${2:-}
	if [ -z "$runner_dir" ] || [ -z "$home" ]; then
		echo "path-guard: 使い方: $0 <runner dir> <home>" >&2
		return 0
	fi
	runner_repair_path_file "$runner_dir/.path" "$home" || true
	return 0
}

# 直接実行されたときだけ入口を呼ぶ（source されたときは関数定義だけ）。
if [ "${BASH_SOURCE[0]}" = "$0" ]; then
	runner_path_guard_main "$@"
	exit 0
fi
