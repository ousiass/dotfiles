# shellcheck shell=bash
# fnm 経由の Node.js LTS installer/updater. common.sh の log/warn に依存。

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
