# shellcheck shell=bash
# herdr installer/updater. common.sh の log/warn に依存。

install_herdr() {
    if command -v herdr >/dev/null 2>&1; then
        log "herdr は既にインストール済み"
        return
    fi
    log "herdr をインストール"
    curl -fsSL https://herdr.dev/install.sh | sh || warn "herdr のインストールに失敗"
}
update_herdr() {
    if ! command -v herdr >/dev/null 2>&1; then
        warn "herdr が無いため update をスキップ"
        return
    fi
    # herdr には公式のセルフアップデートコマンドが未確認なので、
    # インストーラを再実行する（idempotent 想定）。
    log "herdr を更新 (公式インストーラ再実行)"
    curl -fsSL https://herdr.dev/install.sh | sh || warn "herdr の update に失敗"
}
