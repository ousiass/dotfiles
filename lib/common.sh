# shellcheck shell=bash
#
# 共通ヘルパー: ログ・OS 検出・前提チェック・apt/brew パッケージ・symlink。
# install.sh から最初に source される。
#
# 依存するグローバル変数 (install.sh で定義):
#   DOTFILES_DIR, CONFIG_DIR, TIMESTAMP, OS

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
# ~/dotfiles/.env 存在チェック
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

update_brew() {
    [[ "$OS" == "mac" ]] || return 0
    if ! command -v brew >/dev/null 2>&1; then
        warn "brew が無いため update をスキップ"
        return
    fi
    log "Homebrew を更新"
    brew update && brew upgrade || warn "brew の update に失敗"
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
        # brew install を一括で呼ぶと、既に non-brew (公式 pkg / port / 自前ビルド)
        # で入っているパッケージ 1 つの link 衝突等で全部止まるので per-package で。
        # brew 管理下にある pkg はスキップ、失敗したものだけ warn を出して続行する。
        local pkgs=(fish tmux neovim git curl rsync)
        local pkg
        for pkg in "${pkgs[@]}"; do
            if brew list --formula "$pkg" >/dev/null 2>&1; then
                log "$pkg は既にインストール済み"
            else
                brew install "$pkg" || warn "$pkg のインストールに失敗"
            fi
        done
    fi
}

update_packages() {
    if [[ "$OS" == "linux" ]]; then
        if ! command -v apt-get >/dev/null 2>&1; then
            warn "apt-get が無いため packages の update をスキップ"
            return
        fi
        log "apt パッケージを更新（対象のみ --only-upgrade）"
        sudo apt-get update -qq
        sudo apt-get install -y --only-upgrade \
            fish tmux neovim git curl rsync xclip \
            || warn "apt パッケージの update に失敗"
    else
        if ! command -v brew >/dev/null 2>&1; then
            warn "brew が無いため packages の update をスキップ"
            return
        fi
        log "brew パッケージを更新"
        # brew で管理されている pkg だけ upgrade。未インストールに upgrade を
        # 投げると失敗するし、一括だと 1 個失敗で全部止まるので per-package で。
        local pkgs=(fish tmux neovim git curl rsync)
        local pkg
        for pkg in "${pkgs[@]}"; do
            if brew list --formula "$pkg" >/dev/null 2>&1; then
                brew upgrade "$pkg" || warn "$pkg の update に失敗"
            else
                log "$pkg は brew 管理外のためスキップ"
            fi
        done
    fi
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
# ~/dotfiles/.codex/AGENTS.md を ~/.codex/AGENTS.md に symlink
# ------------------------------------------------------------------
# Codex CLI のグローバル指示ファイル。~/.claude/CLAUDE.md と同じ位置付けで、
# 言語設定など全セッション共通の指示を集約する。
link_codex_agents() {
    local src="$DOTFILES_DIR/.codex/AGENTS.md"
    [[ -f "$src" ]] || { warn "$src が無いため AGENTS.md リンクをスキップ"; return; }
    mkdir -p "$HOME/.codex"
    make_symlink "$HOME/.codex/AGENTS.md" "$src" >/dev/null || true
}

# ------------------------------------------------------------------
# ~/dotfiles/.codex/skills/* を ~/.codex/skills/ に symlink
# ------------------------------------------------------------------
# Codex CLI のスキル機構（~/.codex/skills/<name>/SKILL.md）に Claude 用スキルを
# 移植した版をリンクする。~/.codex/skills/.system は Codex 自身が配置する
# ビルトインスキルなので触らない。
link_codex_skills() {
    local src_root="$DOTFILES_DIR/.codex/skills"
    local dst_root="$HOME/.codex/skills"

    [[ -d "$src_root" ]] || { warn "$src_root が無いため Codex skills リンクをスキップ"; return; }
    mkdir -p "$dst_root"

    local skill_dir name
    for skill_dir in "$src_root"/*/; do
        [[ -d "$skill_dir" ]] || continue
        name="$(basename "$skill_dir")"
        # Codex 標準スキル領域は除外（.system 以外も将来増える可能性があるので . 始まりは全除外）
        [[ "$name" == .* ]] && continue
        make_symlink "$dst_root/$name" "$src_root/$name" >/dev/null || true
    done
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
