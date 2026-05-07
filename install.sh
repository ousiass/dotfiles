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

# 各種ツールのインストール先を PATH に先行追加（インストール後すぐ command -v で発見できるように）
export PATH="$HOME/.local/bin:$HOME/.bun/bin:$HOME/.cargo/bin:$HOME/.local/share/fnm:/usr/local/go/bin:$PATH"

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
# 0. ~/dotfiles/.env 存在チェック
# ------------------------------------------------------------------
check_env() {
    if [[ -f "$DOTFILES_DIR/.env" ]]; then
        log "~/dotfiles/.env 確認 OK"
        return
    fi

    err "~/dotfiles/.env が存在しません"
    err ""
    err "セットアップ前に以下を実施してください:"
    err "  1. cp $DOTFILES_DIR/.env.example $DOTFILES_DIR/.env"
    err "  2. \$EDITOR $DOTFILES_DIR/.env  # API キー等を記入"
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
        warn "Go の最新バージョン取得に失敗、Go インストールをスキップ"
        return 0
    fi
    local tarball="${version}.linux-${arch}.tar.gz"
    log "Download: $tarball"
    curl -fsSL "https://go.dev/dl/${tarball}" -o /tmp/go.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf /tmp/go.tar.gz
    rm /tmp/go.tar.gz
}

# ------------------------------------------------------------------
# AI CLI ツール
# ------------------------------------------------------------------
install_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        log "Claude Code は既にインストール済み"
        return
    fi
    log "Claude Code をインストール"
    curl -fsSL https://claude.ai/install.sh | bash
}

install_codex_cli() {
    if command -v codex >/dev/null 2>&1; then
        log "Codex CLI は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため Codex CLI インストールをスキップ"
        return
    fi
    log "Codex CLI をインストール (bun -g @openai/codex)"
    bun install -g @openai/codex
}

install_gemini_cli() {
    if command -v gemini >/dev/null 2>&1; then
        log "Gemini CLI は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため Gemini CLI インストールをスキップ"
        return
    fi
    log "Gemini CLI をインストール (bun -g @google/gemini-cli)"
    bun install -g @google/gemini-cli
}

# ------------------------------------------------------------------
# クラウド / 開発 CLI
# ------------------------------------------------------------------
install_gh() {
    if command -v gh >/dev/null 2>&1; then
        log "gh は既にインストール済み"
        return
    fi
    log "gh (GitHub CLI) をインストール"
    if [[ "$OS" == "mac" ]]; then
        brew install gh
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が見つからないため gh インストールをスキップ"
        return
    fi
    # GitHub 公式手順: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
    local keyring=/usr/share/keyrings/githubcli-archive-keyring.gpg
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee "$keyring" >/dev/null
    sudo chmod go+r "$keyring"
    echo "deb [arch=$(dpkg --print-architecture) signed-by=$keyring] https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y gh
}

install_gcloud() {
    if command -v gcloud >/dev/null 2>&1; then
        log "gcloud は既にインストール済み"
        return
    fi
    log "gcloud (Google Cloud SDK) をインストール"
    if [[ "$OS" == "mac" ]]; then
        brew install --cask google-cloud-sdk
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が見つからないため gcloud インストールをスキップ"
        return
    fi
    # Google 公式手順: https://cloud.google.com/sdk/docs/install#deb
    sudo apt-get install -y apt-transport-https ca-certificates gnupg curl
    local keyring=/usr/share/keyrings/cloud.google.gpg
    curl -fsSL https://packages.cloud.google.com/apt/doc/apt-key.gpg \
        | sudo gpg --batch --yes --dearmor -o "$keyring"
    echo "deb [signed-by=$keyring] https://packages.cloud.google.com/apt cloud-sdk main" \
        | sudo tee /etc/apt/sources.list.d/google-cloud-sdk.list >/dev/null
    sudo apt-get update -qq
    sudo apt-get install -y google-cloud-cli
}

# ------------------------------------------------------------------
# ~/.profile に shell/paths.sh の source 行を冪等に挿入
#
# fish 側は fish/conf.d/paths.fish が起動時に PATH を設定するので、対応する
# bash login shell (~/.profile) からも shell/paths.sh を読み込ませる。
# これで bash interactive / non-interactive (Claude Code の Bash ツール等) /
# IDE 経由の起動でも、go や fnm などのツールを発見できる状態になる。
# ------------------------------------------------------------------
setup_profile_paths() {
    local profile="$HOME/.profile"
    local marker_begin="# >>> dotfiles paths >>>"
    local marker_end="# <<< dotfiles paths <<<"

    if [[ ! -f "$profile" ]]; then
        log "$profile を新規作成"
        : > "$profile"
    fi

    # 既存マーカーブロックがあれば一旦削除（GNU/BSD sed 両対応で -i.bak を使用）
    if grep -qF "$marker_begin" "$profile"; then
        sed -i.bak "/$marker_begin/,/$marker_end/d" "$profile"
        rm -f "$profile.bak"
    fi

    # 末尾にマーカー付きで追記
    cat >> "$profile" <<EOF

$marker_begin
# 自動生成 (install.sh): dotfiles/shell/paths.sh を source して PATH を統一する。
# fish/conf.d/paths.fish と同じパス集合を bash login shell でも有効にする。
if [ -f "$DOTFILES_DIR/shell/paths.sh" ]; then
    . "$DOTFILES_DIR/shell/paths.sh"
fi
$marker_end
EOF
    log "$profile に dotfiles paths セクションを反映"
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
    local target_name="$1"
    local source_path="${2:-$1}"
    make_symlink "$HOME/$target_name" "$DOTFILES_DIR/$source_path" >/dev/null || true
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
    ' || warn "fisher のセットアップで問題あり。手動で 'fisher update' を実行してください"
}

# ------------------------------------------------------------------
# nvim プラグインの初期同期
# ------------------------------------------------------------------
sync_nvim_plugins() {
    if ! command -v nvim >/dev/null 2>&1; then
        warn "nvim が見つからないためプラグイン同期をスキップ"
        return
    fi
    log "nvim プラグインを同期 (lazy.nvim restore: lockfile に合わせて固定)"
    nvim --headless "+Lazy! restore" +qa || warn "lazy.nvim の同期で問題あり（初回は無視可）"
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

    install_claude_code
    install_codex_cli
    install_gemini_cli

    install_gh
    install_gcloud

    link_config nvim
    link_config tmux
    link_config fish
    link_config gh-dash
    link_claude
    link_home_file .env
    link_home_file .mcp.json claude-mcp/mcp.json

    setup_profile_paths
    install_fisher
    install_node_lts
    sync_nvim_plugins
    set_default_shell

    echo
    log "セットアップ完了"
    log "新しいシェルで動作確認してください"
}

main "$@"
