# shellcheck shell=bash
# uv installer/updater. common.sh の log/warn に依存。

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
