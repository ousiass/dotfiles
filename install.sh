#!/usr/bin/env bash
#
# install.sh - dotfiles setup for Ubuntu machines
#
# 使い方:
#   git clone git@github.com:ousiass/dotfiles.git ~/dotfiles
#   cd ~/dotfiles && ./install.sh
#
# 何度実行しても安全（idempotent）。

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------
# 1. apt パッケージ
# ------------------------------------------------------------------
install_packages() {
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が見つからないためパッケージインストールをスキップ"
        return
    fi
    if ! command -v sudo >/dev/null 2>&1; then
        warn "sudo が見つからないためパッケージインストールをスキップ"
        return
    fi

    log "apt パッケージをインストール"
    sudo apt-get update -qq
    sudo apt-get install -y \
        fish \
        tmux \
        neovim \
        git \
        curl \
        xclip
}

# ------------------------------------------------------------------
# 2. シンボリックリンク作成
# ------------------------------------------------------------------
link_config() {
    local name="$1"
    local target="$CONFIG_DIR/$name"
    local source="$DOTFILES_DIR/$name"

    mkdir -p "$CONFIG_DIR"

    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"
        if [[ "$current" == "$source" ]]; then
            log "$target は既に正しくリンク済み"
            return
        fi
        log "$target の既存リンク ($current) を削除"
        rm "$target"
    elif [[ -e "$target" ]]; then
        local backup="$target.bak.$TIMESTAMP"
        log "既存の $target を $backup にバックアップ"
        mv "$target" "$backup"
    fi

    ln -s "$source" "$target"
    log "$target -> $source"
}

# ------------------------------------------------------------------
# 3. secrets ファイルの存在チェック（事前準備が必要）
# ------------------------------------------------------------------
check_secrets() {
    local secrets="$DOTFILES_DIR/fish/conf.d/secrets.fish"
    local example="$DOTFILES_DIR/fish/conf.d/secrets.fish.example"

    if [[ -f "$secrets" ]]; then
        log "secrets.fish 確認 OK"
        return
    fi

    err "secrets.fish が存在しません"
    err ""
    err "セットアップ前に以下を実施してください:"
    err "  1. cp $example $secrets"
    err "  2. \$EDITOR $secrets  # API キー等を記入"
    err "  3. ./install.sh を再実行"
    exit 1
}

# ------------------------------------------------------------------
# 4. fisher と fish プラグイン
# ------------------------------------------------------------------
install_fisher() {
    if ! command -v fish >/dev/null 2>&1; then
        warn "fish が見つからないため fisher セットアップをスキップ"
        return
    fi

    log "fisher と fish プラグインをセットアップ"
    fish -c '
        if not functions -q fisher
            curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
            fisher install jorgebucaran/fisher
        end
        fisher update
    '
}

# ------------------------------------------------------------------
# 5. nvim プラグインの初期同期
# ------------------------------------------------------------------
sync_nvim_plugins() {
    if ! command -v nvim >/dev/null 2>&1; then
        warn "nvim が見つからないためプラグイン同期をスキップ"
        return
    fi
    log "nvim プラグインを同期 (lazy.nvim)"
    nvim --headless "+Lazy! sync" +qa || warn "lazy.nvim の同期で問題あり（初回は無視可）"
}

# ------------------------------------------------------------------
# 6. fish をデフォルトシェルに
# ------------------------------------------------------------------
set_default_shell() {
    local fish_path
    fish_path="$(command -v fish || true)"
    if [[ -z "$fish_path" ]]; then
        warn "fish が見つからないためデフォルトシェル変更をスキップ"
        return
    fi

    if ! grep -qx "$fish_path" /etc/shells 2>/dev/null; then
        log "$fish_path を /etc/shells に追加"
        echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
    fi

    if [[ "${SHELL:-}" == "$fish_path" ]]; then
        log "デフォルトシェルは既に fish"
        return
    fi

    log "デフォルトシェルを fish に変更"
    chsh -s "$fish_path" || warn "chsh に失敗しました（手動で実行してください）"
    warn "→ 再ログインで反映されます"
}

# ------------------------------------------------------------------
main() {
    log "DOTFILES_DIR = $DOTFILES_DIR"
    log "CONFIG_DIR   = $CONFIG_DIR"

    check_secrets
    install_packages
    link_config nvim
    link_config tmux
    link_config fish
    install_fisher
    sync_nvim_plugins
    set_default_shell

    echo
    log "セットアップ完了"
    log "新しいシェルで動作確認してください"
}

main "$@"
