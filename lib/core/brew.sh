# shellcheck shell=bash
# Homebrew の install/update。OS に依存。

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
