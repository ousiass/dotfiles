# shellcheck shell=bash
# GitHub CLI installer/updater. common.sh の log/warn と OS に依存。

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
update_gh() {
    if ! command -v gh >/dev/null 2>&1; then
        warn "gh が無いため update をスキップ"
        return
    fi
    if [[ "$OS" == "mac" ]]; then
        log "gh を更新 (brew upgrade gh)"
        brew upgrade gh || warn "gh の update に失敗"
        return
    fi
    if ! command -v apt-get >/dev/null 2>&1; then
        warn "apt-get が無いため gh の update をスキップ"
        return
    fi
    log "gh を更新 (apt --only-upgrade)"
    sudo apt-get update -qq
    sudo apt-get install -y --only-upgrade gh || warn "gh の update に失敗"
}
