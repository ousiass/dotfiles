#!/usr/bin/env bash
#
# install.sh - dotfiles setup for Ubuntu machines
#
# 使い方:
#   git clone git@github.com:ousiass/dotfiles.git ~/dotfiles
#   cd ~/dotfiles
#   cp .env.example ~/.env && $EDITOR ~/.env   # API キーを記入
#   ./install.sh
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
# 0. ~/.env 存在チェック（事前準備が必要）
# ------------------------------------------------------------------
check_env() {
    if [[ -f "$HOME/.env" ]]; then
        log "~/.env 確認 OK"
        return
    fi

    err "~/.env が存在しません"
    err ""
    err "セットアップ前に以下を実施してください:"
    err "  1. cp $DOTFILES_DIR/.env.example $HOME/.env"
    err "  2. \$EDITOR $HOME/.env  # API キー等を記入"
    err "  3. ./install.sh を再実行"
    exit 1
}

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
        xclip \
        rsync
}

# ------------------------------------------------------------------
# 2. 共通シンボリックリンクヘルパー
# ------------------------------------------------------------------
make_symlink() {
    local target="$1"
    local source="$2"

    mkdir -p "$(dirname "$target")"

    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"
        if [[ "$current" == "$source" ]]; then
            log "$target は既に正しくリンク済み"
            return 1
        fi
        log "$target の既存リンク ($current) を削除"
        rm "$target"
    elif [[ -e "$target" ]]; then
        local backup="$target.bak.$TIMESTAMP"
        log "既存の $target を $backup にバックアップ"
        mv "$target" "$backup"
        # 呼び出し側が backup を使う場合があるので返す
        echo "$backup"
    fi

    ln -s "$source" "$target"
    log "$target -> $source"
    return 0
}

link_config() {
    local name="$1"
    make_symlink "$CONFIG_DIR/$name" "$DOTFILES_DIR/$name" >/dev/null || true
}

link_home_file() {
    local name="$1"
    make_symlink "$HOME/$name" "$DOTFILES_DIR/$name" >/dev/null || true
}

# ------------------------------------------------------------------
# 3. ~/.claude のシンボリックリンク化（ランタイムデータ保全付き）
# ------------------------------------------------------------------
link_claude() {
    local target="$HOME/.claude"
    local source="$DOTFILES_DIR/.claude"

    if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
        log "$target は既に正しくリンク済み"
        return
    fi

    if [[ -L "$target" ]]; then
        log "$target の既存リンクを削除"
        rm "$target"
        ln -s "$source" "$target"
        log "$target -> $source"
        return
    fi

    if [[ -d "$target" ]]; then
        local backup="$target.bak.$TIMESTAMP"
        log "既存の $target を $backup にバックアップ"
        mv "$target" "$backup"
        ln -s "$source" "$target"
        log "$target -> $source"

        # ランタイムデータ（gitignore 対象、history.jsonl/projects/ 等）を
        # dotfiles 側にコピーして移行（既存ファイルは上書きしない）
        log "ランタイムデータを移行（既存は保護）"
        rsync -a --ignore-existing "$backup/" "$source/"
        warn "→ $backup は確認後 \`rm -rf\` で削除可"
        return
    fi

    ln -s "$source" "$target"
    log "$target -> $source"
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

    # ログインシェル確認（getent passwd の最終フィールド）
    local current_shell
    current_shell="$(getent passwd "$USER" | awk -F: '{print $NF}')"
    if [[ "$current_shell" == "$fish_path" ]]; then
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

    check_env
    install_packages
    link_config nvim
    link_config tmux
    link_config fish
    link_claude
    link_home_file .mcp.json
    install_fisher
    sync_nvim_plugins
    set_default_shell

    echo
    log "セットアップ完了"
    log "新しいシェルで動作確認してください"
}

main "$@"
