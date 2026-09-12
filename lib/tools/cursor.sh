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

# ------------------------------------------------------------------
# ~/dotfiles/.claude/skills/* を ~/.cursor/skills/ に symlink
# ------------------------------------------------------------------
# Cursor CLI は互換で ~/.claude/skills/ も読むが、Cloud Agents の同期対象は
# ~/.cursor/skills/ のみ。自作スキル（Claude 側が単一の正）をそちらにも配る。
# ~/.agents/skills/ への symlink（外部 agent-skills）は link_agent_skills が
# 直接リンクするのでここでは除外する。
link_cursor_skills() {
    local src_root="$DOTFILES_DIR/.claude/skills"
    local dst_root="$HOME/.cursor/skills"

    [[ -d "$src_root" ]] || { warn "$src_root が無いため Cursor skills リンクをスキップ"; return; }
    mkdir -p "$dst_root"

    local skill_dir name src dst current
    for skill_dir in "$src_root"/*/; do
        [[ -d "$skill_dir" ]] || continue
        name="$(basename "$skill_dir")"
        [[ "$name" == .* ]] && continue

        src="$src_root/$name"
        [[ -L "$src" ]] && continue

        # 上書きしていいのは「存在しない」or「既に同じ src を指す」場合のみ。
        # 実体ディレクトリや別ソースを指す symlink は保護する。
        dst="$dst_root/$name"
        if [[ -L "$dst" ]]; then
            current="$(readlink "$dst")"
            if [[ "$current" != "$src" ]]; then
                warn "$dst は既存リンク ($current) と衝突するため link をスキップ"
                continue
            fi
        elif [[ -e "$dst" ]]; then
            warn "$dst は既存ディレクトリと衝突するため link をスキップ"
            continue
        fi
        make_symlink "$dst" "$src" >/dev/null || true
    done
}
