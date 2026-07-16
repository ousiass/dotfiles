#!/usr/bin/env bash
#
# update.sh - インストール済みツールを最新版へ
#
# install.sh が初回セットアップ用なのに対し、こちらは既にインストール済みの
# 各ツールを最新版に更新する用途。各ツールごとに公式の update コマンドを呼ぶ。
# 個別の失敗は warn を出して続行し、最後まで走り切る。
#
# 使い方:
#   ./update.sh           # 全ツールを更新
#   make update           # 同上 (Makefile 経由)

set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
OS=""

# install.sh と同じ前置き PATH（update が走る前に各ツールを発見できるように）
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.local/share/fnm:/usr/local/go/bin:$PATH"

# shellcheck source=lib/load.sh
. "$DOTFILES_DIR/lib/load.sh"

main() {
    log "DOTFILES_DIR = $DOTFILES_DIR"
    detect_os

    # 引数指定で個別 update_* だけ走らせる（例: ./update.sh codex_fugu codex）
    if [[ $# -gt 0 ]]; then
        for target in "$@"; do
            local fn="update_${target}"
            if ! declare -F "$fn" >/dev/null; then
                err "$fn は未定義です"
                exit 1
            fi
            "$fn"
        done
        return
    fi

    update_brew
    update_packages
    update_neovim

    update_uv
    update_bun
    update_rustup
    update_fnm
    update_go
    update_node_lts

    update_claude_code
    update_fugu
    update_codex_cli
    update_gemini_cli
    update_herdr

    update_lazygit
    update_gh
    update_gcloud
    update_cloudflared
    update_wrangler
    update_netlify_cli
    update_pm2

    update_moleport
    update_linterly

    update_agent_skills

    update_fisher
    update_nvim_plugins

    echo
    log "アップデート完了"
}

main "$@"
