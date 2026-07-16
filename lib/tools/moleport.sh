# shellcheck shell=bash
# MolePort installer/updater. common.sh の log/warn に依存。

install_moleport() {
    if command -v moleport >/dev/null 2>&1; then
        log "MolePort は既にインストール済み"
        return
    fi
    if ! command -v go >/dev/null 2>&1; then
        warn "go が見つからないため MolePort インストールをスキップ"
        return
    fi
    log "MolePort をインストール (go install)"
    go install github.com/ousiassllc/moleport/cmd/moleport@latest
}
update_moleport() {
    if ! command -v go >/dev/null 2>&1; then
        warn "go が無いため MolePort の update をスキップ"
        return
    fi
    log "MolePort を更新 (go install ...@latest)"
    go install github.com/ousiassllc/moleport/cmd/moleport@latest \
        || warn "moleport の update に失敗"
}
