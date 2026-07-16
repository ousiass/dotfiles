# shellcheck shell=bash
# fnm installer/updater. common.sh の log/warn に依存。

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
