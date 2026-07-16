# shellcheck shell=bash
# bun installer/updater. common.sh の log/warn に依存。

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
