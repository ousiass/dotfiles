#!/usr/bin/env bash
# GitHub Actions self-hosted runner ホストのセットアップ
#   - Linux: systemd / apt 系
#   - macOS: Apple Silicon（arm64）/ launchd / colima（Intel の Mac と Docker Desktop は対象外）
#
# 出所: https://github.com/ousiassllc/actions-runner-setup-base （vendored copy）
#       上流を更新したらこのファイルも追従させる。
#       （macOS 対応はこのコピー側で先に入れている。上流へ取り込むときは差分に注意）
#
# ジョブ実行の前提（パスワード不要 sudo / Docker / Buildx / C コンパイラ。Linux はさらに docker グループ）を
# 整え、登録済み runner をサービス（Linux: systemd / macOS: launchd）として起動する。
#
# 前提: config.sh による runner の登録が済んでいること（.runner が存在すること）。
#       未登録の場合は先に ./config.sh --url ... --token ... を実行する。
#       macOS は加えて、runner ユーザーが GUI でログインしていること（LaunchAgent は GUI セッションに
#       登録するため。別ユーザーでの実行やログイン前・SSH だけの実行は対象外として止まる）と、
#       Xcode コマンドラインツール・Homebrew が入っていること（無ければ入れ方を案内して止まる）。
#       colima / docker / docker-buildx / fnm / gh / jq などは runner-tools-install.sh が
#       runner ユーザーとして brew で入れる（入っているものは飛ばす。Homebrew 自体・Xcode 本体・
#       署名証明書は入れない）。再起動後の自動ログインは設定しない（README の前提）。
#
# 実行:
#   make runner-setup
#   make runner-setup RUNNER_USER=ci-runner RUNNER_DIR=/opt/runners/foo
#   sudo bash runner-host-setup.sh
#   sudo RUNNER_USER=ci-runner RUNNER_DIR=/opt/runners/foo bash runner-host-setup.sh
#
# 既定値:
#   RUNNER_USER  sudo を呼び出したユーザー（${SUDO_USER}）
#   RUNNER_DIR   $RUNNER_USER のホームディレクトリ配下の actions-runner
#
# 失敗したらその場で止まる（set -e）。何度実行しても同じ結果になる。
#
# PATH の扱い（runner-path-guard.sh が定義と判定を持つ）:
#   runner のサービス（runsvc.sh）は起動時に <runner dir>/.path があれば PATH を
#   丸ごとそれで上書きする。.env の PATH= より後に効くので、.path が PATH の正になる。
#   そのためこのスクリプトは .path と .env の両方へ安定 PATH を書き、さらに起動のたびに
#   .path を検査して外れていれば自動修復するガードを設置する。
#     Linux : systemd drop-in の ExecStartPre
#     macOS : launchd の plist の ProgramArguments（ガード経由で runsvc.sh へ exec する）

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=runner-path-guard.sh
. "$SCRIPT_DIR/runner-path-guard.sh"

# 既定値は固定。テストが /etc を触らずに済むよう、環境変数で向け先だけ差し替えられる。
SUDOERS_FILE="${SUDOERS_FILE:-/etc/sudoers.d/github-runner}"
SYSTEMD_SYSTEM_DIR="${SYSTEMD_SYSTEM_DIR:-/etc/systemd/system}"

OS="$(uname -s)"
case "$OS" in
Linux) ;;
Darwin)
	# Rosetta 下の端末では uname -m が x86_64 になるため、CPU 自体が arm64 かを sysctl で見る。
	if [ "$(uname -m)" != arm64 ] && [ "$(sysctl -n hw.optional.arm64 2>/dev/null || true)" != 1 ]; then
		echo "対象外です: macOS は Apple Silicon（arm64）のみ対応しています（このホスト: $(uname -m)）。" >&2
		echo "Intel の Mac は対象外です。" >&2
		exit 1
	fi
	# brew は /opt/homebrew/bin。sudo 経由では PATH に無いことがあるので、後ろへ足して探せるようにする。
	# 環境変数 RUNNER_BREW_PATHS で差し替えられる（runner-tools-install.sh と同じ変数名・既定値。
	# 空にすると何も足さない。`:-` ではなく `-` なので空文字も有効）。テストが、実機の本物の brew を
	# 拾わないようにするため。
	RUNNER_BREW_PATHS="${RUNNER_BREW_PATHS-/opt/homebrew/bin:/opt/homebrew/sbin}"
	if [ -n "$RUNNER_BREW_PATHS" ]; then
		export PATH="$PATH:$RUNNER_BREW_PATHS"
	fi
	;;
*)
	echo "対象外です: 未対応の OS です: ${OS}（Linux と macOS のみ対応）" >&2
	exit 1
	;;
esac

if [ "$(id -u)" -ne 0 ]; then
	echo "root で実行してください: sudo bash $0" >&2
	exit 1
fi

# runner を実行するユーザー。svc.sh install [user] に渡す値と一致させる。
RUNNER_USER="${RUNNER_USER:-${SUDO_USER:-}}"
if [ -z "$RUNNER_USER" ]; then
	echo "RUNNER_USER を決められません（sudo 経由でないため \$SUDO_USER が空です）。" >&2
	echo "RUNNER_USER=<user> を指定してください: sudo RUNNER_USER=ci-runner bash $0" >&2
	exit 1
fi

# ユーザーのホームディレクトリ。macOS には getent が無いので dscl で取る。
runner_user_home() {
	case "$OS" in
	Darwin) dscl . -read "/Users/$1" NFSHomeDirectory 2>/dev/null | sed -n 's/^NFSHomeDirectory:[[:space:]]*//p' ;;
	*) getent passwd "$1" | cut -d: -f6 ;;
	esac
}

if ! home=$(runner_user_home "$RUNNER_USER") || [ -z "$home" ]; then
	echo "ユーザーが見つかりません: $RUNNER_USER" >&2
	exit 1
fi

# macOS: LaunchAgent は GUI ログイン中のセッションにだけ登録できる。runner ユーザーが
# コンソールにログインしている前提で、そうでなければ対象外として止める（別ユーザーでの実行や
# ログイン前・SSH だけのホストは想定しない）。
if [ "$OS" = Darwin ]; then
	console_user=$(stat -f %Su /dev/console 2>/dev/null || true)
	if [ -z "$console_user" ] || [ "$console_user" = root ]; then
		# /dev/console の所有者が root のとき（ログイン画面のまま）か、取れなかったとき（GUI の無い環境）
		echo "対象外です: macOS では、runner ユーザー（${RUNNER_USER}）が GUI でログインしている必要があります（いまは誰もログインしていません）。" >&2
		echo "  ${RUNNER_USER} で GUI ログインしたまま、そのユーザーのターミナルから実行してください。ログイン前・SSH だけの実行は対象外です。" >&2
		exit 1
	fi
	if [ "$console_user" != "$RUNNER_USER" ]; then
		echo "対象外です: macOS では、runner ユーザー（${RUNNER_USER}）が GUI でログインしている必要があります（現在のログインユーザー: ${console_user}）。" >&2
		echo "  ${RUNNER_USER} に切り替えてログインしたまま、そのユーザーのターミナルから実行してください。別ユーザーでの実行は対象外です。" >&2
		exit 1
	fi
fi

RUNNER_DIR="${RUNNER_DIR:-$home/actions-runner}"

if [ ! -x "$RUNNER_DIR/svc.sh" ]; then
	echo "runner ディレクトリが見つかりません: $RUNNER_DIR" >&2
	echo "RUNNER_DIR=<path> で指定してください。" >&2
	exit 1
fi

# .runner は config.sh が作る。未登録のまま svc.sh install しても起動できない。
if [ ! -f "$RUNNER_DIR/.runner" ]; then
	echo "runner が未登録です（$RUNNER_DIR/.runner がありません）。" >&2
	echo "先に config.sh で登録してください: cd $RUNNER_DIR && ./config.sh --url <URL> --token <TOKEN>" >&2
	exit 1
fi

# ジョブの shell 相当の PATH（OS ごとに runner-path-guard.sh が定義する）。
runner_path=$(runner_stable_path "$home")

# macOS: runner ユーザーとして、ジョブと同じ最小環境（非ログイン）でコマンドを実行する。
# root のままだと colima の docker context（ユーザーの ~/.docker）が見えない。
runner_exec() {
	(cd / && sudo -u "$RUNNER_USER" -H env -i HOME="$home" PATH="$runner_path" "$@")
}

# サービス管理（svc.sh）。macOS の svc.sh は root での実行を拒否し、実行したユーザーの
# LaunchAgent（~/Library/LaunchAgents）として登録するため、runner ユーザーで呼ぶ。
# 呼び出し元は $RUNNER_DIR にいること。
run_svc() {
	if [ "$OS" = Darwin ]; then
		sudo -u "$RUNNER_USER" -H ./svc.sh "$@"
	else
		./svc.sh "$@"
	fi
}

echo "runner user: $RUNNER_USER"
echo "runner dir : $RUNNER_DIR"
echo

echo "== 1/5 パスワード不要 sudo =="
# ariga/setup-atlas が sudo install で /usr/local/bin へ atlas を置くため必須。
#
# 検証してから設置する。壊れた内容を /etc/sudoers.d/ へ置くと sudo 自体が使えなくなり、
# その端末からの復旧手段を失うため（tee してから visudo -c だと壊れた状態が一瞬でも残る）。
#
# 注意: NOPASSWD: ALL は、この runner で走る任意のワークフローに実質 root を与える。
# runner group の対象リポジトリを限定し、public リポジトリへ提供しないことが前提。
#
# macOS の root のプライマリグループは wheel（root グループは無い）。
if [ "$OS" = Darwin ]; then
	root_group=wheel
else
	root_group=root
fi
if [ -f "$SUDOERS_FILE" ] && grep -qE "^${RUNNER_USER}[[:space:]]+ALL=\(ALL\)[[:space:]]+NOPASSWD:[[:space:]]*ALL$" "$SUDOERS_FILE"; then
	echo "  既に設定済み: $SUDOERS_FILE"
else
	tmp=$(mktemp)
	printf '%s ALL=(ALL) NOPASSWD: ALL\n' "$RUNNER_USER" >"$tmp"
	chmod 0440 "$tmp"
	visudo -c -f "$tmp"
	install -m 0440 -o root -g "$root_group" "$tmp" "$SUDOERS_FILE"
	rm -f "$tmp"
	visudo -c
	echo "  設置: $SUDOERS_FILE"
fi

if [ "$OS" = Darwin ]; then
	echo "== 2/5 Xcode CLT / Homebrew / ツール（colima / docker / docker-buildx など）=="
	# Xcode CLT（GUI のダイアログが出る）と Homebrew（所有者がユーザー）は、このスクリプトでは入れず、
	# 足りなければ入れ方を案内して止まる。それ以外のツールは下で runner-tools-install.sh が入れる。
	#
	# cc（C コンパイラ）は Xcode コマンドラインツールが提供する。go test -race は cgo を必要とし、
	# actions/setup-go は C コンパイラを入れない。
	if ! xcode-select -p >/dev/null 2>&1; then
		echo "Xcode コマンドラインツール（C コンパイラ cc）が入っていません。" >&2
		echo "  xcode-select --install を実行し、インストールが終わってからもう一度実行してください。" >&2
		exit 1
	fi
	echo "  Xcode コマンドラインツール: $(xcode-select -p)"
	if ! brew_bin=$(command -v brew); then
		echo "Homebrew が見つかりません。" >&2
		echo "  https://brew.sh の手順で入れ（Apple Silicon の既定は /opt/homebrew）、もう一度実行してください。" >&2
		exit 1
	fi
	echo "  Homebrew: $brew_bin"
	# 足りないツール（colima / docker / docker-buildx / fnm / gh / jq / shellcheck など）は
	# runner-tools-install.sh が、runner ユーザーとして brew で入れる（入っているものは飛ばす）。
	# Homebrew 自体・Xcode 本体・署名証明書は入れない（案内か表示だけ）。
	# docker-buildx 単体では docker CLI から見えないことがある。その場合は最後の確認で案内する。
	sudo -u "$RUNNER_USER" -H env PATH="$PATH" RUNNER_BREW_PATHS="$RUNNER_BREW_PATHS" bash "$SCRIPT_DIR/runner-tools-install.sh"
	echo "  runner に要るツール: そろっている"

	echo "== 3/5 colima =="
	# brew services は runner ユーザーの LaunchAgent（homebrew.mxcl.colima）として登録するので、
	# runner ユーザーのログイン後に自動で上がる。起動済みなら何もしない。
	sudo -u "$RUNNER_USER" -H "$brew_bin" services start colima
	docker_ready=0
	for _ in {1..60}; do
		if runner_exec docker info >/dev/null 2>&1; then
			docker_ready=1
			break
		fi
		sleep 2
	done
	if [ "$docker_ready" -ne 1 ]; then
		echo "  colima の docker に接続できません（2 分待った）。runner ユーザーで colima status / brew services info colima を確認してください。" >&2
		exit 1
	fi
	echo "  $RUNNER_USER で docker info が通った"
else
	echo "== 2/5 Docker / Buildx / Compose / C コンパイラ / zstd =="
	# docker.io 単体では buildx が入らず、COPY --chmod を含む Dockerfile が
	# 「the --chmod option requires BuildKit」で失敗するため docker-buildx を明示する。
	#
	# build-essential は go test -race のため。競合検出は cgo（= gcc）を必要とし、
	# actions/setup-go は Go ツールチェーンだけを入れて C コンパイラは入れない。
	export DEBIAN_FRONTEND=noninteractive
	apt-get update
	# zstd は actions/cache が tar の圧縮に使う。docker-compose-v2 は Ubuntu の docker.io 前提の
	# `docker compose` 用。すでに `docker compose version` が通るホスト（Docker 公式 apt の
	# docker-compose-plugin など）では、cli-plugins/docker-compose が衝突するので入れない。
	# docker.io 自体は従来どおり無条件に入れる（docker-ce のホストへの適用は想定しない）。
	packages=(docker.io docker-buildx build-essential zstd)
	if ! docker compose version >/dev/null 2>&1; then
		packages+=(docker-compose-v2)
	fi
	apt-get install -y "${packages[@]}"
	systemctl enable --now docker

	echo "== 3/5 docker グループ =="
	# usermod は既存プロセスに反映されない。この後で svc.sh install / start するので
	# 新しいプロセスとして起動され、runner の再起動は不要になる。
	# 既にサービスが動いている状態で実行した場合は 4/5 の svc.sh start では足りず、
	# systemctl restart が必要になる（そのため 5/5 で稼働プロセスの Groups を検査する）。
	usermod -aG docker "$RUNNER_USER"
	echo "  $RUNNER_USER の所属: $(id -nG "$RUNNER_USER")"
fi

if [ "$OS" = Darwin ]; then svc_manager=launchd; else svc_manager=systemd; fi
echo "== 4/5 PATH 設定と $svc_manager サービス化 =="
# ジョブの shell は非ログイン・最小環境で起動するため、fish の fnm 初期化も
# shell/paths.sh も読まれず node / npx が見えない（exit 127）。
# 安定 PATH（runner-path-guard.sh の runner_stable_path）を runner に渡す。fnm の
# aliases/default は node の更新に追従するシンボリックリンクなので、バージョンを固定せずに済む。
#
# 渡し口は 2 つ。実効的に効くのは .path（runsvc.sh が PATH を丸ごと上書きするため、.env より優先）。
#   - <runner dir>/.path : 後述（svc.sh install の後で書く）
#   - <runner dir>/.env  : Listener が読む。二重化だが害は少ない
# PATH= 行は置き換えるだけで、何度実行しても重複しない。
env_file="$RUNNER_DIR/.env"
# 稼働中の runner へ反映するには再起動が必要な変更があったか（.path / .env / macOS の plist）。
needs_restart=0
if [ ! -e "$env_file" ]; then
	: >"$env_file"
	chown "$RUNNER_USER" "$env_file"
	chmod 644 "$env_file"
fi
if grep -qxF "PATH=$runner_path" "$env_file"; then
	echo "  $env_file の PATH は設定済み"
else
	# sed -i は GNU と BSD で引数が違うため使わない。cat で書き戻して所有者・権限を保つ。
	tmp=$(mktemp)
	# grep -v は 1 行も残らないとき rc=1。読み取りエラー（rc=2）は握りつぶさず止める。
	grep -v '^PATH=' "$env_file" >"$tmp" || [ $? -eq 1 ]
	cat "$tmp" >"$env_file"
	rm -f "$tmp"
	# 末尾が改行で終わっていないと直前の行に連結されてしまう。
	if [ -s "$env_file" ] && [ -n "$(tail -c1 "$env_file")" ]; then
		echo >>"$env_file"
	fi
	echo "PATH=$runner_path" >>"$env_file"
	needs_restart=1
	echo "  $env_file に PATH を設定した"
fi

cd "$RUNNER_DIR"
if [ -f .service ]; then
	echo "  既にサービス化済み: $(cat .service)"
elif [ "$OS" = Darwin ]; then
	# launchd の svc.sh はユーザー引数を取らない（sudo -u で渡したユーザーの LaunchAgent になる）。
	run_svc install
else
	./svc.sh install "$RUNNER_USER"
fi
# Linux: systemd の unit 名 / macOS: LaunchAgent の plist のパス
unit=$(cat .service)

# .path は svc.sh install / config.sh を実行したシェルの PATH で書かれる。
# svc.sh install が書き直す可能性があるため、その後で検査・修復する。
path_file="$RUNNER_DIR/.path"
rc=0
runner_repair_path_file "$path_file" "$home" || rc=$?
case "$rc" in
0)
	chown "$RUNNER_USER" "$path_file"
	needs_restart=1
	echo "  $path_file を安定 PATH に設定した"
	;;
1) echo "  $path_file は書き換え不要" ;;
*)
	echo "  $path_file を修復できませんでした" >&2
	exit 1
	;;
esac

# 起動のたびに .path を検査して自動修復するガードを設置する。
# ガードは runner ユーザーで走り、runner dir 内の .path だけを触る。
guard_script="$RUNNER_DIR/path-guard.sh"
install -m 755 -o "$RUNNER_USER" "$SCRIPT_DIR/runner-path-guard.sh" "$guard_script"

if [ "$OS" = Darwin ]; then
	# launchd に ExecStartPre 相当は無いので、plist の ProgramArguments を
	#   path-guard.sh --exec <runner dir> <home>
	# に差し替える。ガードが .path を直してから runsvc.sh へ exec する（起動のたびに走る）。
	# plist は svc.sh install が生成した既知の形（ProgramArguments が runsvc.sh 1 要素）を前提にし、
	# 想定と違えば壊さずに止まる。所有者を保つため mv せず中身を書き戻す。
	# 修復内容は <home>/Library/Logs/<label>/stdout.log で追える。
	plist="$unit"
	label=$(basename "$plist" .plist)
	if [ ! -f "$plist" ]; then
		echo "  LaunchAgent の plist が見つかりません: ${plist}（.service と食い違っています。svc.sh uninstall してから再実行してください）" >&2
		exit 1
	fi
	if grep -qF "<string>$guard_script</string>" "$plist"; then
		echo "  既に設置済み: $plist"
	else
		runsvc_line="<string>$RUNNER_DIR/runsvc.sh</string>"
		new_plist=$(mktemp)
		found=0
		while IFS= read -r line || [ -n "$line" ]; do
			if [[ "$line" == *"$runsvc_line"* ]]; then
				indent="${line%%<*}"
				printf '%s<string>%s</string>\n' "$indent" "$guard_script"
				printf '%s<string>--exec</string>\n' "$indent"
				printf '%s<string>%s</string>\n' "$indent" "$RUNNER_DIR"
				printf '%s<string>%s</string>\n' "$indent" "$home"
				found=1
			else
				printf '%s\n' "$line"
			fi
		done <"$plist" >"$new_plist"
		if [ "$found" -ne 1 ]; then
			rm -f "$new_plist"
			echo "  plist の ProgramArguments が想定と違うため書き換えません: ${plist}（$runsvc_line が見つかりません）" >&2
			exit 1
		fi
		# 書き戻す前に検証する（壊れた plist を置くと launchd が runner を読み込めなくなる）。
		if command -v plutil >/dev/null 2>&1 && ! plutil -lint "$new_plist" >/dev/null; then
			rm -f "$new_plist"
			echo "  生成した plist が不正なため書き換えません: $plist" >&2
			exit 1
		fi
		cat "$new_plist" >"$plist"
		rm -f "$new_plist"
		needs_restart=1
		echo "  設置: $plist の ProgramArguments をガード経由にした"
	fi

	# plist / .path / .env は起動（load）時にしか読まれない。稼働中の runner は、ジョブ
	# （Runner.Worker）が走っていなければ再起動し、走っていれば再起動を促すだけにする。
	# svc.sh start（launchctl load）は読み込み済みだと失敗するため、稼働中のときは呼ばない。
	was_active=0
	# 完全一致で見る（actions.runner.org-repo.mac は ...mac2 の部分文字列になるため、list の出力は grep しない）。
	sudo -u "$RUNNER_USER" -H launchctl list "$label" >/dev/null 2>&1 && was_active=1
	if [ "$was_active" -eq 0 ]; then
		run_svc start
	elif [ "$needs_restart" -eq 1 ]; then
		if pgrep -u "$RUNNER_USER" -f Runner.Worker >/dev/null; then
			echo "  ジョブ実行中のため runner を再起動していません。反映するには" >&2
			echo "  ジョブが無くなってから runner ユーザーで cd $RUNNER_DIR && ./svc.sh stop && ./svc.sh start を実行してください" >&2
		else
			run_svc stop
			run_svc start
			echo "  設定反映のため runner を再起動した"
		fi
	else
		echo "  既に起動済み: $label"
	fi
else
	# ガードは systemd drop-in の ExecStartPre で起動のたびに実行する。
	# 修復内容は journalctl -u $unit で追える。
	dropin_dir="$SYSTEMD_SYSTEM_DIR/$unit.d"
	dropin_file="$dropin_dir/path-guard.conf"
	dropin_body="[Service]
ExecStartPre=\"$guard_script\" \"$RUNNER_DIR\" \"$home\""
	if [ -f "$dropin_file" ] && [ "$(cat "$dropin_file")" = "$dropin_body" ]; then
		echo "  既に設置済み: $dropin_file"
	else
		mkdir -p "$dropin_dir"
		printf '%s\n' "$dropin_body" >"$dropin_file"
		echo "  設置: $dropin_file"
	fi
	# 内容が同じでも副作用は無い。drop-in を読み込ませてから起動する。
	systemctl daemon-reload

	# .path / .env は runner の起動時にだけ読まれる。稼働中だった場合は再起動が必要だが、
	# 実行中のジョブ（Runner.Worker）を落とさないよう、ジョブが無いときだけ行う。
	was_active=0
	systemctl is-active --quiet "$unit" && was_active=1
	./svc.sh start
	if [ "$needs_restart" -eq 1 ] && [ "$was_active" -eq 1 ]; then
		if pgrep -u "$RUNNER_USER" -f Runner.Worker >/dev/null; then
			echo "  ジョブ実行中のため runner を再起動していません。PATH を反映するには" >&2
			echo "  ジョブが無くなってから sudo systemctl restart $unit を実行してください" >&2
		else
			systemctl restart "$unit"
			echo "  PATH 反映のため runner を再起動した"
		fi
	fi
fi

echo "== 5/5 確認 =="
if [ "$OS" = Darwin ]; then
	# macOS には /proc も docker グループも無い。runner ユーザーが、ジョブと同じ最小環境で
	# docker / buildx / node / cc を使えるかで確かめる。
	echo "--- runner ユーザーの docker ---"
	runner_exec docker --version
	if runner_exec docker info >/dev/null 2>&1; then
		echo "  OK: $RUNNER_USER で docker info が通る"
	else
		echo "  NG: $RUNNER_USER で docker info が通りません（colima status を確認）" >&2
	fi
	runner_exec docker buildx version \
		|| echo "  NG: docker buildx が使えません（runner-tools-install.sh が ~/.docker/config.json の cliPluginsExtraDirs に足しているはずです。make runner-tools を流し直し、brew info docker-buildx の caveats と見比べてください）" >&2
	echo "--- .path の PATH から node / npx / cc ---"
	# .path が PATH の正（runsvc.sh が丸ごと上書きする）。それだけを頼りに引けるかを見る。
	if sudo -u "$RUNNER_USER" -H env -i HOME="$home" PATH="$(<"$path_file")" bash --noprofile --norc -c 'command -v node npx cc'; then
		echo "  OK: .path の PATH で node / npx / cc が見える"
	else
		echo "  NG: .path の PATH では node / npx / cc が見えません（fnm で node を入れ、fnm default を設定してください。cc は xcode-select --install）" >&2
	fi
else
	docker --version
	docker buildx version
	gcc --version | head -1
	echo "--- Runner.Listener の実 PATH から node / npx ---"
	# .env を見るだけでは、runsvc.sh が .path で PATH を上書きするバグを検知できない。
	# 稼働中の Listener の環境変数（/proc/<pid>/environ）が本当の PATH なので、それを検査する。
	# 再起動直後は Listener がまだ居ないことがあるので、少し待つ。
	pid=""
	for _ in 1 2 3 4 5 6 7 8 9 10; do
		pid=$(pgrep -u "$RUNNER_USER" -f Runner.Listener | head -1 || true)
		[ -n "$pid" ] && break
		sleep 1
	done
	if [ -n "$pid" ]; then
		listener_path=$(tr '\0' '\n' <"/proc/$pid/environ" | sed -n 's/^PATH=//p' | head -1)
		if [[ ":$listener_path:" != *":$home/.local/share/fnm/aliases/default/bin:"* ]]; then
			echo "  NG: Runner.Listener (pid $pid) の PATH に $home/.local/share/fnm/aliases/default/bin がありません" >&2
			echo "      PATH=$listener_path" >&2
			echo "      sudo systemctl restart $unit を実行してください（.path は ${path_file}）" >&2
		elif sudo -u "$RUNNER_USER" -H env -i HOME="$home" PATH="$listener_path" bash --noprofile --norc -c 'command -v node npx'; then
			echo "  OK: Runner.Listener (pid $pid) の PATH で node / npx が見える"
		else
			echo "  NG: Runner.Listener (pid $pid) の PATH では node / npx が見えません（fnm で node を入れ、fnm default を設定してください）" >&2
		fi
	else
		echo "  Runner.Listener が見つかりません（起動直後なら数秒待って systemctl status $unit を確認）" >&2
	fi
fi
echo "--- コンテナ内の名前解決 ---"
# docker build 中の DNS 障害は、デプロイが長時間待ってから落ちて初めて気づくため
# セットアップ時点で検知する。自動修正はしない（/etc/docker/daemon.json の "dns" はホスト固有）。
if [ "$OS" = Darwin ]; then
	runner_exec docker run --rm alpine nslookup proxy.golang.org >/dev/null 2>&1 \
		|| echo "  NG: コンテナから名前解決できません (colima の dns 設定を確認: README の GitHub Actions self-hosted runner 節)" >&2
else
	docker run --rm alpine nslookup proxy.golang.org >/dev/null 2>&1 \
		|| echo "  NG: コンテナから名前解決できません (docker の dns 設定を確認: README の GitHub Actions self-hosted runner 節)" >&2
fi
echo "--- NOPASSWD sudo ---"
sudo -l -U "$RUNNER_USER" | grep -i nopasswd || echo "  NOPASSWD が見つかりません" >&2
echo "--- runner サービス ---"
if [ "$OS" = Darwin ]; then
	run_svc status || true
else
	systemctl is-enabled "$unit" || true
	systemctl is-active "$unit" || true
	echo "--- runner のグループ反映（稼働プロセス）---"
	# gsr-helper の doctor（job.dockergroup）と同じ判定。「グループ追加済みなのに
	# permission denied が出続ける」= 稼働プロセスへの未反映を切り分けるため。
	# 上で見つけた Listener（pid）をそのまま使う。
	if [ -n "$pid" ]; then
		docker_gid=$(getent group docker | cut -d: -f3)
		# Groups 行だけを見る。status 全体を grep すると Pid や Uid の数値に当たる。
		groups_line=$(awk '/^Groups:/{$1=""; print}' "/proc/$pid/status")
		if printf ' %s ' $groups_line | grep -q " ${docker_gid} "; then
			echo "  OK: Runner.Listener (pid $pid) は docker グループを持っている"
		else
			echo "  NG: Runner.Listener (pid $pid) に docker グループが反映されていない" >&2
			echo "      sudo systemctl restart $unit を実行してください" >&2
		fi
	else
		echo "  Runner.Listener が見つかりません（起動直後なら数秒待って systemctl status $unit を確認）" >&2
	fi
fi

echo
if [ "$OS" = Darwin ]; then
	cat <<EOS

次にやること（このスクリプトからは検証できない）:

  ラベル
    runner のラベルに macOS と ARM64 が付いていること。runs-on: [self-hosted, macOS, ARM64]
    は 3 つを AND で要求し、欠けているとジョブはエラーにならず無期限に queued で止まる。
    $home/Library/Logs/$label/stdout.log で Listening for Jobs の後に Running job が出れば付いている。

  ログイン
    runner も colima も runner ユーザーの LaunchAgent なので、そのユーザーが macOS にログインして
    いる間だけ動く。再起動後も動かすには、そのユーザーの自動ログインを設定する。

  runner group の対象リポジトリ（admin:org 権限が必要 / API から機械的に検証できない）
    org の Settings -> Actions -> Runner groups で確認する。
      - 対象リポジトリを「選択したリポジトリ」にし、使うリポジトリだけを明示的に追加する
      - public リポジトリへの提供は既定（提供しない）のまま変更しない
    NOPASSWD: ALL を入れた以上、ここが fork PR 経由で第三者のコードが
    この runner 上で走ることを防ぐ唯一の層になる。
EOS
else
	cat <<EOS

次にやること（このスクリプトからは検証できない）:

  ラベル
    runner のラベルに linux と x64 が付いていること。runs-on: [self-hosted, linux, x64]
    は 3 つを AND で要求し、欠けているとジョブはエラーにならず無期限に queued で止まる。
    journalctl -u $unit で Listening for Jobs の後に Running job が出れば付いている。

  runner group の対象リポジトリ（admin:org 権限が必要 / API から機械的に検証できない）
    org の Settings -> Actions -> Runner groups で確認する。
      - 対象リポジトリを「選択したリポジトリ」にし、使うリポジトリだけを明示的に追加する
      - public リポジトリへの提供は既定（提供しない）のまま変更しない
    NOPASSWD: ALL を入れた以上、ここが fork PR 経由で第三者のコードが
    この runner 上で走ることを防ぐ唯一の層になる。
EOS
fi
