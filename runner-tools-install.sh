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

install_macos() {
	# Xcode コマンドラインツール（C コンパイラ cc）。go test -race の cgo に必要。
	if ! xcode-select -p >/dev/null 2>&1; then
		err "Xcode コマンドラインツール（C コンパイラ cc）が入っていません。"
		err "  xcode-select --install を実行し、インストールが終わってからもう一度実行してください。"
		exit 1
	fi
	log "Xcode コマンドラインツール: $(xcode-select -p)"

	# sudo 経由などで PATH に無いことがあるので、Apple Silicon の既定の場所を後ろへ足す。
	export PATH="$PATH:/opt/homebrew/bin:/opt/homebrew/sbin"
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

	ensure_node_default
	report_apple_extras
}

install_linux() {
	if ! command -v apt-get >/dev/null 2>&1; then
		err "apt-get が見つかりません（apt 系の Linux だけ対応）。"
		exit 1
	fi

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
