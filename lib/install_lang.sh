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
