# shellcheck shell=bash
# Linterly installer/updater. common.sh の log/warn に依存。

install_linterly() {
    if command -v linterly >/dev/null 2>&1; then
        log "Linterly は既にインストール済み"
        return
    fi
    if ! command -v go >/dev/null 2>&1; then
        warn "go が見つからないため Linterly インストールをスキップ"
        return
    fi
    log "Linterly をインストール (go install)"
    go install github.com/ousiassllc/linterly/cmd/linterly@latest
}
update_linterly() {
    if ! command -v go >/dev/null 2>&1; then
        warn "go が無いため Linterly の update をスキップ"
        return
    fi
    log "Linterly を更新 (go install ...@latest)"
    go install github.com/ousiassllc/linterly/cmd/linterly@latest \
        || warn "linterly の update に失敗"
}
