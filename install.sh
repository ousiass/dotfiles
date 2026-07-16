#!/usr/bin/env bash
#
# install.sh - dotfiles setup for Ubuntu / macOS
#
# 使い方:
#   git clone git@github.com:ousiass/dotfiles.git ~/dotfiles
#   cd ~/dotfiles
#   cp .env.example ~/.env && $EDITOR ~/.env   # API キー等を記入
#   ./install.sh
#
# 何度実行しても安全（idempotent）。
# 実体は lib/ 配下に分割されている:
#   lib/common.sh       — ログ、OS 検出、apt/brew、symlink ヘルパー
#   lib/install_lang.sh — uv / bun / rustup / fnm / go / Node LTS
#   lib/install_cli.sh  — claude / codex / gemini / gh / gcloud
#   lib/setup_shell.sh  — ~/.profile, fisher, nvim 同期, default shell

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OS=""

# 各種ツールのインストール先を PATH に先行追加（インストール後すぐ command -v で発見できるように）
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.local/share/fnm:/usr/local/go/bin:$PATH"

# lib/ から関数を読み込む。common.sh は他から log/warn/err を参照されるので最初。
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/install_lang.sh
. "$DOTFILES_DIR/lib/install_lang.sh"
# shellcheck source=lib/install_cli.sh
. "$DOTFILES_DIR/lib/install_cli.sh"
# shellcheck source=lib/setup_shell.sh
. "$DOTFILES_DIR/lib/setup_shell.sh"

main() {
    log "DOTFILES_DIR = $DOTFILES_DIR"

    # 引数指定で個別 install_* だけ走らせる（例: ./install.sh fugu codex_cli）
    # 全体セットアップを通さずに 1 ツールだけ入れ直したい場合に使う。
    if [[ $# -gt 0 ]]; then
        detect_os
        for target in "$@"; do
            local fn="install_${target}"
            if ! declare -F "$fn" >/dev/null; then
                err "$fn は未定義です"
                exit 1
            fi
            "$fn"
        done
        return
    fi

    log "CONFIG_DIR   = $CONFIG_DIR"

    detect_os
    check_env
    install_brew
    install_packages
    install_neovim

    install_uv
    install_bun
    install_rustup
    install_fnm
    install_go

    install_claude_code
    install_fugu
    install_codex_cli
    install_gemini_cli
    install_herdr

    install_gh
    install_gcloud
    install_cloudflared
    install_wrangler
    install_netlify_cli
    install_pm2

    install_moleport
    install_linterly

    link_config nvim
    link_config tmux
    link_config fish
    link_config gh-dash
    link_config herdr
    link_claude
    link_codex_agents
    link_codex_skills
    sync_codex_mcp
    install_agent_skills
    link_home_file .env
    link_home_file .mcp.json claude-mcp/mcp.json

    setup_profile_paths
    setup_global_gitignore
    install_fisher
    install_node_lts
    sync_nvim_plugins
    set_default_shell

    echo
    log "セットアップ完了"
    log "新しいシェルで動作確認してください"
}

main "$@"
