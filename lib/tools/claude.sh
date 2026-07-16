# shellcheck shell=bash
# Claude Code installer/updater. common.sh の log/warn に依存。

install_claude_code() {
    if command -v claude >/dev/null 2>&1; then
        log "Claude Code は既にインストール済み"
        return
    fi
    log "Claude Code をインストール"
    curl -fsSL https://claude.ai/install.sh | bash
}
update_claude_code() {
    if ! command -v claude >/dev/null 2>&1; then
        warn "claude が無いため update をスキップ"
        return
    fi
    if [[ -n "${CLAUDECODE:-}" ]]; then
        warn "Claude Code セッション中のため claude update をスキップ"
        warn "  → Claude Code を終了してから 'claude update' を手動実行してください"
        return
    fi
    log "Claude Code を更新 (claude update)"
    claude update || warn "claude update に失敗"
}
