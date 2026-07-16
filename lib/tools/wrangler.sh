# shellcheck shell=bash
# wrangler installer/updater. common.sh の log/warn に依存。

install_wrangler() {
    if command -v wrangler >/dev/null 2>&1; then
        log "wrangler は既にインストール済み"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため wrangler インストールをスキップ"
        return
    fi
    log "wrangler をインストール (bun -g wrangler)"
    bun install -g wrangler
}
update_wrangler() {
    if ! command -v wrangler >/dev/null 2>&1; then
        warn "wrangler が無いため update をスキップ"
        return
    fi
    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が無いため wrangler の update をスキップ"
        return
    fi
    log "wrangler を更新 (bun update -g wrangler)"
    bun update -g wrangler || warn "wrangler の update に失敗"
}
