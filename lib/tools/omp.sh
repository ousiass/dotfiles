# shellcheck shell=bash
# oh-my-pi (omp) installer/updater. common.sh の log/warn に依存。

# ------------------------------------------------------------------
# oh-my-pi (omp)
# ------------------------------------------------------------------
# LSP/DAP を内蔵したコーディングエージェント CLI（badlogic/pi-mono のフォーク）。
# 公式インストーラに --binary を渡して prebuilt バイナリ固定で入れる。
#   - bun -g 経由だと keytar / onnxruntime-node の postinstall が bun にブロックされる
#   - Apple Silicon で Rosetta 版 bun があると x86_64 バイナリが生成され、
#     起動が遅く AVX 警告が出る（インストーラ自身が警告する既知の罠）
# 配置先は $HOME/.local/bin（install.sh 冒頭の PATH 先行追加に含まれる）。
install_omp() {
    if command -v omp >/dev/null 2>&1; then
        log "omp は既にインストール済み"
        return
    fi
    log "omp をインストール (公式インストーラ --binary)"
    curl -fsSL https://omp.sh/install | sh -s -- --binary \
        || warn "omp のインストールに失敗"
}

# インストーラは再実行で最新版に入れ替わるので update も同じ経路を使う。
update_omp() {
    if ! command -v omp >/dev/null 2>&1; then
        warn "omp が無いため update をスキップ"
        return
    fi
    log "omp を更新 (公式インストーラ --binary)"
    curl -fsSL https://omp.sh/install | sh -s -- --binary \
        || warn "omp の update に失敗"
}

# ~/.omp/agent/ にはセッション DB (agent.db) やキャッシュも同居するため、
# ディレクトリごとではなく config.yml だけを symlink する。
link_omp() {
    local dst_dir="$HOME/.omp/agent"
    mkdir -p "$dst_dir"
    make_symlink "$dst_dir/config.yml" "$DOTFILES_DIR/omp/config.yml" >/dev/null || true
    # MCP 定義は Claude / Codex と同じ claude-mcp/mcp.json を共有する。
    # omp の探索先は ~/.omp/agent/mcp.json や ~/.claude.json 等で、
    # ~/.mcp.json（ホーム直下）は見ないため明示的にリンクする。
    make_symlink "$dst_dir/mcp.json" "$DOTFILES_DIR/claude-mcp/mcp.json" >/dev/null || true
    # omp は .claude/agents を意図的にスキップする（frontmatter 契約が違う）ため、
    # omp 用のサブエージェント定義を専用ディレクトリごとリンクする。
    # 常時適用のユーザールール。omp は user レベルの ~/.claude/CLAUDE.md を読まないため、
    # Claude Code と同じ実体を RULES.md という名前でリンクする（内容の二重管理をしない）。
    make_symlink "$dst_dir/RULES.md" "$DOTFILES_DIR/.claude/CLAUDE.md" >/dev/null || true
    # advisor だけが読む注意書き。user レベルの WATCHDOG.md として拾われる。
    make_symlink "$dst_dir/WATCHDOG.md" "$DOTFILES_DIR/omp/WATCHDOG.md" >/dev/null || true
    make_symlink "$dst_dir/agents" "$DOTFILES_DIR/omp/agents" >/dev/null || true
    # session_stop 等のイベントに載る拡張。omp は settings.json の hooks.Stop を
    # 解釈しないため、sweep の停止ガードはここで供給する。
    [[ -d "$DOTFILES_DIR/omp/extensions" ]] \
        && make_symlink "$dst_dir/extensions" "$DOTFILES_DIR/omp/extensions" >/dev/null || true
    # omp native provider (priority 100) は claude provider (80) より優先されるので、
    # ここに置いた同名スキルが ~/.claude/skills 版を上書きする。無ければ Claude 版にフォールバック。
    [[ -d "$DOTFILES_DIR/omp/skills" ]] \
        && make_symlink "$dst_dir/skills" "$DOTFILES_DIR/omp/skills" >/dev/null || true
    return 0
}
