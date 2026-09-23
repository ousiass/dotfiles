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
    # NONINTERACTIVE=1: 「Press RETURN/ENTER to continue」の確認待ちを飛ばす。
    # 付けないと install.sh 全体が Homebrew の入力待ちで止まる。
    # 管理者権限自体は必須なので、sudo パスワードは 1 回だけ聞かれる。
    NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
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
