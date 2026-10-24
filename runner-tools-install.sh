#!/usr/bin/env bash
# self-hosted runner のジョブが使うツールのうち、入っていないものだけを入れる。
# すでに入っているものは飛ばすので、何度実行しても同じ結果になる。
#
# 実行（runner を動かすユーザー自身で。root / sudo では動かさない）:
#   make runner-tools
#   ./runner-tools-install.sh
#
# macOS（Apple Silicon）は runner-host-setup.sh が、runner ユーザーとしてこのスクリプトを呼ぶ。
# Linux は runner-host-setup.sh からは呼ばない（Docker / Buildx / build-essential は
# runner-host-setup.sh が apt で入れる）。足したいときだけ make runner-tools を単体で実行する。
#
# 入れるもの:
#   macOS : Homebrew で colima docker docker-buildx fnm gh jq shellcheck fish
#           ＋ fnm で Node.js LTS（default に設定）
#           ＋ ~/.docker/config.json に docker context colima（currentContext）と buildx のプラグインの場所
#             （cliPluginsExtraDirs）。colima の docker に繋がり、docker buildx が使えるようにする
#   Linux : apt で jq shellcheck fish、install.sh と同じ関数（lib/tools/）で fnm と gh、
#           ＋ fnm で Node.js LTS（default に設定）
#
# 入れないもの（無いときは表示するだけ）:
#   - Homebrew 自体（無ければ入れ方を案内して止まる）
#   - Xcode 本体（Xcode.app）とコード署名の証明書
#   - Xcode コマンドラインツール（無ければ xcode-select --install を案内して止まる。GUI の確認が出るため）

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export LOG_TAG=runner-tools

# shellcheck source=lib/core/log.sh
. "$DOTFILES_DIR/lib/core/log.sh"
# shellcheck source=lib/core/os.sh
. "$DOTFILES_DIR/lib/core/os.sh"
# shellcheck source=lib/tools/fnm.sh
. "$DOTFILES_DIR/lib/tools/fnm.sh"
# shellcheck source=lib/tools/gh.sh
. "$DOTFILES_DIR/lib/tools/gh.sh"

# 入れ損ねたもの（空白区切り）。最後にまとめて報告して失敗で終わる。
failed=""
note_failure() { failed="$failed $1"; }

# brew は root では動かない。fnm / Node も実行ユーザーのホームに入る。
if [ "$(id -u)" -eq 0 ]; then
	err "root では実行できません。runner を動かすユーザーで実行してください（sudo を付けない）。"
	exit 1
fi

# fnm の default に Node.js LTS が設定されているようにする。
# runner の安定 PATH（runner-path-guard.sh）は fnm の aliases/default/bin を指すため、
# fnm の default が無いと、ジョブの中で node / npx が見えない。
ensure_node_default() {
	export PATH="$HOME/.local/share/fnm:$PATH"
	if ! command -v fnm >/dev/null 2>&1; then
		warn "fnm が見つからないため Node.js の準備をスキップ"
		note_failure fnm
		return
	fi
	if fnm exec --using=default node --version >/dev/null 2>&1; then
		log "Node.js（fnm の default）は設定済み"
		return
	fi
	log "Node.js LTS を fnm でインストールし、default に設定"
	if ! { fnm install --lts && fnm default lts-latest; }; then
		warn "Node.js の準備に失敗"
		note_failure node
	fi
}

# Xcode 本体とコード署名の証明書は、入れずに有無だけ表示する（ライセンス同意・Apple ID・秘密鍵が要るため）。
report_apple_extras() {
	local xcode_app="${XCODE_APP:-/Applications/Xcode.app}"
	if [ -d "$xcode_app" ]; then
		log "Xcode 本体: あり（${xcode_app}）"
	else
		warn "Xcode 本体が入っていません（${xcode_app}）。xcodebuild が要るジョブには App Store から手動で入れてください。このスクリプトでは入れません。"
	fi
	if security find-identity -v -p codesigning 2>/dev/null | grep -Eq '^ *[1-9][0-9]* valid identit'; then
		log "コード署名の証明書: あり"
	else
		warn "コード署名の証明書が見つかりません。署名が要るジョブには、キーチェーンへ手動で入れてください。このスクリプトでは入れません。"
	fi
}

# colima の docker に runner ユーザー（ジョブ・docker info の確認・対話シェル）から繋がるようにする。
# どれも runner ユーザーの ~/.docker/config.json に書くので、sudo も環境変数も要らず、再起動後も残る。
#   1. docker context: colima の socket（~/.colima/default/docker.sock。colima の既定プロファイル）を指す
#      context "colima" が無ければ作り、currentContext にする。無いと docker は /var/run/docker.sock を見て失敗する。
#      colima 自身も起動時に同名の context を作ることがあるので、あれば作らずそのまま使う。
#      runner 専用ホストの前提で、currentContext が別の値でも colima に切り替える（切り替えたことは表示する）。
#   2. cliPluginsExtraDirs: brew の docker-buildx は $(brew --prefix)/lib/docker/cli-plugins に入るが、
#      docker CLI の探索先に無いので `docker buildx` が unknown command になる。その場所を足す。
# 他のキーは残したまま足す。すでに設定済みなら何も書かない（何度流しても同じ結果）。
ensure_docker_config() {
	if ! command -v docker >/dev/null 2>&1 || ! command -v jq >/dev/null 2>&1; then
		warn "docker または jq が見つからないため、docker の設定（context / buildx）をスキップ"
		return
	fi
	local docker_dir="$HOME/.docker" cfg="$HOME/.docker/config.json" socket="$HOME/.colima/default/docker.sock"
	local plugin_dir tmp current
	mkdir -p "$docker_dir"
	[ -s "$cfg" ] || echo '{}' >"$cfg"
	if ! jq empty "$cfg" >/dev/null 2>&1; then
		warn "${cfg} が JSON として読めないため、docker の設定（context / buildx）をスキップ（壊れた設定は上書きしません）"
		note_failure docker-config
		return
	fi

	plugin_dir="$(brew --prefix 2>/dev/null)/lib/docker/cli-plugins"
	if [ ! -d "$plugin_dir" ]; then
		warn "docker-buildx のプラグインの場所が見つかりません（${plugin_dir}）。docker buildx は使えません。"
	elif jq -e --arg d "$plugin_dir" '(.cliPluginsExtraDirs // []) | index($d)' "$cfg" >/dev/null 2>&1; then
		log "cliPluginsExtraDirs は設定済み（${plugin_dir}）"
	else
		tmp=$(mktemp)
		if jq --arg d "$plugin_dir" '.cliPluginsExtraDirs = ((.cliPluginsExtraDirs // []) + [$d])' "$cfg" >"$tmp"; then
			cat "$tmp" >"$cfg"
			log "cliPluginsExtraDirs に ${plugin_dir} を追加（docker buildx 用）"
		else
			warn "cliPluginsExtraDirs の設定に失敗"
			note_failure docker-config
		fi
		rm -f "$tmp"
	fi

	if ! docker context inspect colima >/dev/null 2>&1; then
		log "docker context colima を作成（${socket}）"
		docker context create colima --docker "host=unix://${socket}" >/dev/null || {
			warn "docker context colima の作成に失敗"
			note_failure docker-config
			return
		}
	fi
	current=$(jq -r '.currentContext // "default"' "$cfg" 2>/dev/null || echo default)
	if [ "$current" = colima ]; then
		log "docker の currentContext は colima のまま"
	else
		log "docker の currentContext を ${current} から colima に切り替え"
		docker context use colima >/dev/null || {
			warn "docker context use colima に失敗"
			note_failure docker-config
		}
	fi
}

install_macos() {
	# Xcode コマンドラインツール（C コンパイラ cc）。go test -race の cgo に必要。
	if ! xcode-select -p >/dev/null 2>&1; then
		err "Xcode コマンドラインツール（C コンパイラ cc）が入っていません。"
		err "  xcode-select --install を実行し、インストールが終わってからもう一度実行してください。"
		exit 1
	fi
	log "Xcode コマンドラインツール: $(xcode-select -p)"

	# sudo 経由などで PATH に無いことがあるので、Apple Silicon の既定の場所を後ろへ足す。
	# 環境変数 RUNNER_BREW_PATHS で差し替えられる（runner-host-setup.sh と同じ変数名・既定値。
	# 空にすると何も足さない。`:-` ではなく `-` なので空文字も有効）。テストが、実機の
	# /opt/homebrew の本物の brew を拾わないようにするため。
	local brew_paths="${RUNNER_BREW_PATHS-/opt/homebrew/bin:/opt/homebrew/sbin}"
	if [ -n "$brew_paths" ]; then
		export PATH="$PATH:$brew_paths"
	fi
	if ! command -v brew >/dev/null 2>&1; then
		err "Homebrew が見つかりません。このスクリプトでは自動で入れません。"
		err "  https://brew.sh の手順で入れ（Apple Silicon の既定は /opt/homebrew）、もう一度実行してください。"
		exit 1
	fi

	# 1 つ失敗しても残りは試す（既に non-brew で入っている pkg の link 衝突などで全部が止まらないように）。
	local formulae=(colima docker docker-buildx fnm gh jq shellcheck fish) formula
	for formula in "${formulae[@]}"; do
		if brew list --formula "$formula" >/dev/null 2>&1; then
			log "${formula} は既にインストール済み"
		else
			log "${formula} をインストール"
			brew install "$formula" || {
				warn "${formula} のインストールに失敗"
				note_failure "$formula"
			}
		fi
	done

	ensure_docker_config
	ensure_node_default
	report_apple_extras
}

install_linux() {
	if ! command -v apt-get >/dev/null 2>&1; then
		err "apt-get が見つかりません（apt 系の Linux だけ対応）。"
		exit 1
	fi

	# install_fnm は command -v fnm だけで入っているかを見る。fnm の公式インストーラの置き場所を
	# 先に PATH へ足しておかないと、PATH に無い runner ユーザーでは毎回ダウンロードし直してしまう
	# （install.sh / lib/tools/node_lts.sh と同じ形）。
	export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"

	local packages=(jq shellcheck fish) pkg missing=()
	for pkg in "${packages[@]}"; do
		if command -v "$pkg" >/dev/null 2>&1; then
			log "${pkg} は既にインストール済み"
		else
			missing+=("$pkg")
		fi
	done
	if [ "${#missing[@]}" -gt 0 ]; then
		log "apt パッケージをインストール: ${missing[*]}"
		sudo apt-get update -qq
		sudo apt-get install -y "${missing[@]}" || note_failure "apt(${missing[*]})"
	fi

	# install.sh と同じ関数。どちらも入っていれば何もしない。
	install_fnm
	install_gh
	ensure_node_default
}

detect_os
case "$OS" in
mac) install_macos ;;
linux) install_linux ;;
esac

if [ -n "$failed" ]; then
	err "インストールできなかったもの:${failed}"
	exit 1
fi
log "runner に要るツールはそろっています"
