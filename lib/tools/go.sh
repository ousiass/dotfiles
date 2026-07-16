# shellcheck shell=bash
# Go installer/updater. common.sh の log/warn と OS に依存。

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

update_go() {
    if ! command -v go >/dev/null 2>&1; then
        warn "go が無いため update をスキップ"
        return
    fi
    if [[ "$OS" == "mac" ]]; then
        log "Go を更新 (brew upgrade go)"
        brew upgrade go || warn "go の update に失敗"
        return
    fi

    # Linux: install_go と同じ tarball ダウンロード処理。バージョン比較を入れて
    # 既に最新ならスキップする。
    local arch
    arch=$(uname -m)
    case "$arch" in
        x86_64) arch=amd64 ;;
        aarch64) arch=arm64 ;;
    esac
    local latest current
    latest=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1)
    current=$(go version 2>/dev/null | awk '{print $3}')
    if [[ -z "$latest" ]]; then
        warn "Go の最新バージョン取得に失敗、go の update をスキップ"
        return
    fi
    if [[ "$current" == "$latest" ]]; then
        log "Go は既に最新 ($current)"
        return
    fi
    log "Go を更新: $current -> $latest"
    local tarball="${latest}.linux-${arch}.tar.gz"
    curl -fsSL "https://go.dev/dl/${tarball}" -o /tmp/go.tar.gz \
        && sudo rm -rf /usr/local/go \
        && sudo tar -C /usr/local -xzf /tmp/go.tar.gz \
        || warn "go の update に失敗"
    rm -f /tmp/go.tar.gz
}
