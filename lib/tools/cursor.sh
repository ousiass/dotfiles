# shellcheck shell=bash
# Cursor CLI (cursor-agent) installer/updater. common.sh の log/warn に依存。

install_cursor() {
    install_cursor_cli "$@"
}
install_cursor_cli() {
    if command -v cursor-agent >/dev/null 2>&1; then
        log "Cursor CLI は既にインストール済み ($(cursor_cli_version || echo unknown))"
        return
    fi
    log "Cursor CLI をインストール"
    cursor_cli_run_installer || warn "Cursor CLI のインストールに失敗"
}

# 公式インストーラは ~/.local/share/cursor-agent/versions/<ver>/ に展開し、
# ~/.local/bin/{cursor-agent,agent} から symlink する
# （PATH は install.sh 冒頭で先行追加済み）。常に最新版を取得する。
cursor_cli_run_installer() {
    curl -fsS https://cursor.com/install | bash
}

cursor_cli_version() {
    cursor-agent --version 2>/dev/null | head -n1
}

# cursor-agent は shell ツール実行時に子プロセスへ CURSOR_AGENT=1 を渡す。
# これを自セッション判定に使い、自分自身の差し替えを避ける。
cursor_session_active() {
    [[ -n "${CURSOR_AGENT:-}" ]]
}

update_cursor() {
    update_cursor_cli "$@"
}
update_cursor_cli() {
    if ! command -v cursor-agent >/dev/null 2>&1; then
        warn "cursor-agent が無いため update をスキップ"
        return
    fi
    if cursor_session_active; then
        warn "Cursor CLI セッション中のため cursor-agent update をスキップ"
        warn "  → Cursor CLI を終了してから 'cursor-agent update' を手動実行してください"
        return
    fi

    log "Cursor CLI を更新 (cursor-agent update)"
    if cursor-agent update; then
        return
    fi

    # 長く放置したバイナリのセルフアップデートは無言で失敗することがある
    # （実測: 2025.09 版は "Checking for updates..." のまま exit 1）。
    # 公式インストーラは常に最新版を取るので、そちらにフォールバックする。
    warn "cursor-agent update に失敗したため公式インストーラで再取得"
    cursor_cli_run_installer || warn "Cursor CLI の update に失敗"
}
