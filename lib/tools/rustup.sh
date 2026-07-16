# shellcheck shell=bash
# rustup installer/updater. common.sh の log/warn に依存。

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
