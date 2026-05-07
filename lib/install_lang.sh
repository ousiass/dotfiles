# shellcheck shell=bash
#
# 言語ツール（公式インストーラ経由）と Node LTS。
# uv / bun / rustup / fnm / go と、fnm 経由の Node LTS 取得をまとめる。

install_uv() {
    if command -v uv >/dev/null 2>&1; then
        log "uv は既にインストール済み"
        return
    fi
    log "uv をインストール"
    curl -LsSf https://astral.sh/uv/install.sh | sh
}

update_uv() {
    if ! command -v uv >/dev/null 2>&1; then
        warn "uv が無いため update をスキップ"
        return
    fi
    log "uv を更新 (uv self update)"
    uv self update || warn "uv の update に失敗"
}

install_bun() {
    if command -v bun >/dev/null 2>&1; then
        log "bun は既にインストール済み"
        return
    fi
    log "bun をインストール"
    curl -fsSL https://bun.sh/install | bash
}

update_bun() {
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が無いため update をスキップ"
        return
    fi
    log "bun を更新 (bun upgrade)"
    bun upgrade || warn "bun の update に失敗"
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

update_rustup() {
    if ! command -v rustup >/dev/null 2>&1; then
        warn "rustup が無いため update をスキップ"
        return
    fi
    log "rustup を更新 (rustup self update + rustup update)"
    rustup self update || warn "rustup self update に失敗"
    rustup update || warn "rustup update (toolchain) に失敗"
}

install_fnm() {
    if command -v fnm >/dev/null 2>&1; then
        log "fnm は既にインストール済み"
        return
    fi
    log "fnm をインストール"
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell
}

update_fnm() {
    if ! command -v fnm >/dev/null 2>&1; then
        warn "fnm が無いため update をスキップ"
        return
    fi
    # fnm に self-update は無いので公式インストーラを再実行（最新バイナリで上書き）
    log "fnm を更新（公式インストーラを再実行）"
    curl -fsSL https://fnm.vercel.app/install | bash -s -- --skip-shell \
        || warn "fnm の update に失敗"
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

update_node_lts() {
    export PATH="$HOME/.local/share/fnm:$HOME/.local/bin:$PATH"
    if ! command -v fnm >/dev/null 2>&1; then
        warn "fnm が無いため Node の update をスキップ"
        return
    fi
    log "Node.js LTS を最新へ (fnm install --lts)"
    eval "$(fnm env --shell bash)"
    fnm install --lts || warn "fnm install --lts に失敗"
    fnm default lts-latest || warn "fnm default lts-latest に失敗"
}
