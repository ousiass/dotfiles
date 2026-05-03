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

set -euo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"
OS=""

log()  { printf '\033[1;34m[install]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

# ------------------------------------------------------------------
# OS 検出
# ------------------------------------------------------------------
detect_os() {
    case "$(uname -s)" in
        Linux)  OS=linux ;;
        Darwin) OS=mac ;;
        *) err "Unsupported OS: $(uname -s)"; exit 1 ;;
    esac
    log "OS: $OS"
}

# ------------------------------------------------------------------
# 0. ~/.env 存在チェック
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
# Homebrew (macOS only)
# ------------------------------------------------------------------
install_brew() {
    [[ "$OS" == "mac" ]] || return 0
    if command -v brew >/dev/null 2>&1; then
        log "Homebrew は既にインストール済み"
        return
    fi
    log "Homebrew をインストール"
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    # 現在のセッションで brew を使えるようにする
    if [[ -d /opt/homebrew ]]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [[ -x /usr/local/bin/brew ]]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi
}

# ------------------------------------------------------------------
# システムパッケージ
# ------------------------------------------------------------------
install_packages() {
    if [[ "$OS" == "linux" ]]; then
        if ! command -v apt-get >/dev/null 2>&1; then
            warn "apt-get が見つからないためパッケージインストールをスキップ"
            return
        fi
        log "apt パッケージをインストール"
        sudo apt-get update -qq
        sudo apt-get install -y \
            fish tmux neovim git curl rsync xclip
    else
        log "brew パッケージをインストール"
        brew install fish tmux neovim git curl rsync
    fi
}

# ------------------------------------------------------------------
# 言語ツール（公式インストーラ）
# ------------------------------------------------------------------
install_uv() {
    if command -v uv >/dev/null 2>&1; then
        log "uv は既にインストール済み"
        return
    fi
    log "uv をインストール"
    curl -LsSf https://astral.sh/uv/install.sh | sh
}

install_bun() {
    if command -v bun >/dev/null 2>&1; then
        log "bun は既にインストール済み"
        return
    fi
    log "bun をインストール"
    curl -fsSL https://bun.sh/install | bash
}

install_rustup() {
    if command -v rustup >/dev/null 2>&1; then
        log "rustup は既にインストール済み"
        return
    fi
    log "rustup をインストール"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs \
        | sh -s -- -y --default-toolchain stable --no-modify-path
}

install_fnm() {
    if command -v fnm >/dev/null 2>&1; then
        log "fnm は既にインストール済み"
        return
    fi
    log "fnm をインストール"
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
}

install_go() {
    if command -v go >/dev/null 2>&1; then
        log "Go は既にインストール済み"
        return
    fi
    log "Go をインストール"
    if [[ "$OS" == "mac" ]]; then
        brew install go
        return
    fi

    # Linux: 公式 tarball を /usr/local/go へ
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch=amd64 ;;
        aarch64) arch=arm64 ;;
    esac
    local version
    version=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)
    if [[ -z "$version" ]]; then
        err "Go の最新バージョン取得に失敗"
        return 1
    fi
    local tarball="${version}.linux-${arch}.tar.gz"
    log "Download: $tarball"
    curl -fsSL "https://go.dev/dl/${tarball}" -o /tmp/go.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
}

# ------------------------------------------------------------------
# 各ツールのバイナリパスを fish の universal path に追加
# ------------------------------------------------------------------
setup_fish_paths() {
    if ! command -v fish >/dev/null 2>&1; then
        warn "fish が見つからないため fish_user_paths 設定をスキップ"
        return
    fi
    log "fish_user_paths にツールパスを追加"
    fish -c '
        for p in $HOME/.local/bin $HOME/.bun/bin $HOME/.cargo/bin $HOME/.local/share/fnm /usr/local/go/bin /opt/homebrew/bin /opt/homebrew/sbin
            if test -d $p
                fish_add_path -U $p
            end
        end
    '
}

# ------------------------------------------------------------------
# fnm 経由で Node LTS をインストール
# ------------------------------------------------------------------
install_node_lts() {
    export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"
    if ! command -v fnm >/dev/null 2>&1; then
        warn "fnm が見つからないため Node インストールをスキップ"
        return
    fi
    log "Node.js LTS を fnm でインストール"
    eval "$(fnm env --shell bash)"
    fnm install --lts
    fnm default lts-latest
}

# ------------------------------------------------------------------
# 共通シンボリックリンクヘルパー
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
# ~/.claude のシンボリックリンク化（ランタイムデータ保全付き）
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

        log "ランタイムデータを移行（既存は保護）"
        rsync -a --ignore-existing "$backup/" "$source/"
        warn "→ $backup は確認後 \`rm -rf\` で削除可"
        return
    fi

    ln -s "$source" "$target"
    log "$target -> $source"
}

# ------------------------------------------------------------------
# fisher と fish プラグイン
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
# nvim プラグインの初期同期
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
# fish をデフォルトシェルに
# ------------------------------------------------------------------
get_login_shell() {
    if [[ "$OS" == "mac" ]]; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$USER" | awk -F: '{print $NF}'
    fi
}

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

    local current_shell
    current_shell="$(get_login_shell)"
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

    detect_os
    check_env
    install_brew
    install_packages

    install_uv
    install_bun
    install_rustup
    install_fnm
    install_go

    link_config nvim
    link_config tmux
    link_config fish
    link_claude
    link_home_file .mcp.json

    setup_fish_paths
    install_fisher
    install_node_lts
    sync_nvim_plugins
    set_default_shell

    echo
    log "セットアップ完了"
    log "新しいシェルで動作確認してください"
}

main "$@"
