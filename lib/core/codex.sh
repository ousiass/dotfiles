# shellcheck shell=bash
# Codex 設定・MCP・skills の link/sync。DOTFILES_DIR と make_symlink に依存。

# ------------------------------------------------------------------
# ~/dotfiles/.codex/AGENTS.md を ~/.codex/AGENTS.md に symlink
# ------------------------------------------------------------------
# Codex CLI のグローバル指示ファイル。~/.claude/CLAUDE.md と同じ位置付けで、
# 言語設定など全セッション共通の指示を集約する。
link_codex_agents() {
    local src="$DOTFILES_DIR/.codex/AGENTS.md"
    [[ -f "$src" ]] || { warn "$src が無いため AGENTS.md リンクをスキップ"; return; }
    mkdir -p "$HOME/.codex"
    make_symlink "$HOME/.codex/AGENTS.md" "$src" >/dev/null || true
}

# ------------------------------------------------------------------
# ~/dotfiles/claude-mcp/mcp.json を Codex の MCP 設定に同期
# ------------------------------------------------------------------
# Claude と Codex で同じ MCP サーバー（supabase, deepwiki, 等）を共有するため、
# Claude 用の mcp.json から `codex mcp add` で再登録する。
# env interpolation（`${VAR}` 形式）は Codex がプロセス環境を継承するため
# `--env` 渡しは不要（fish の secrets.fish で export 済み）。リテラル値の env
# のみ `--env` で渡す。`codex mcp login` 等で別管理されているプラグイン MCP
# （github 等）には触れない。
sync_codex_mcp() {
    local src="$DOTFILES_DIR/claude-mcp/mcp.json"
    [[ -f "$src" ]] || { warn "$src が無いため Codex MCP 同期をスキップ"; return; }
    command -v jq >/dev/null 2>&1 || { warn "jq が無いため Codex MCP 同期をスキップ"; return; }
    command -v codex >/dev/null 2>&1 || { warn "codex が無いため Codex MCP 同期をスキップ"; return; }

    log "Claude の MCP 設定を Codex に同期"

    local names
    names=$(jq -r '.mcpServers // {} | keys[]' "$src")
    [[ -z "$names" ]] && { log "mcpServers が空のためスキップ"; return; }

    local name type err
    while IFS= read -r name; do
        type=$(jq -r ".mcpServers[\"$name\"].type // \"stdio\"" "$src")
        codex mcp remove "$name" >/dev/null 2>&1 || true

        if [[ "$type" == "http" ]]; then
            local url
            url=$(jq -r ".mcpServers[\"$name\"].url" "$src")
            if err=$(codex mcp add "$name" --url "$url" 2>&1); then
                log "  + $name (http: $url)"
            else
                warn "  ! $name の登録に失敗: ${err//$'\n'/ }"
            fi
        else
            local cmd_bin
            cmd_bin=$(jq -r ".mcpServers[\"$name\"].command" "$src")
            local -a args=() env_args=()
            local arg k v
            while IFS= read -r arg; do
                args+=("$arg")
            done < <(jq -r ".mcpServers[\"$name\"].args[]?" "$src")
            while IFS=$'\t' read -r k v; do
                [[ -z "$k" ]] && continue
                # ${VAR} 形式は Codex の親プロセス env 継承に任せる
                [[ "$v" =~ ^\$\{[A-Za-z_][A-Za-z0-9_]*\}$ ]] && continue
                env_args+=(--env "$k=$v")
            done < <(jq -r ".mcpServers[\"$name\"].env // {} | to_entries[] | \"\(.key)\t\(.value)\"" "$src")

            if err=$(codex mcp add "$name" "${env_args[@]+"${env_args[@]}"}" -- "$cmd_bin" "${args[@]+"${args[@]}"}" 2>&1); then
                log "  + $name (stdio: $cmd_bin ${args[*]+${args[*]}})"
            else
                warn "  ! $name の登録に失敗: ${err//$'\n'/ }"
            fi
        fi
    done <<< "$names"
}

# ------------------------------------------------------------------
# ~/dotfiles/.codex/skills/* を ~/.codex/skills/ に symlink
# ------------------------------------------------------------------
# Codex CLI のスキル機構（~/.codex/skills/<name>/SKILL.md）に Claude 用スキルを
# 移植した版をリンクする。~/.codex/skills/.system は Codex 自身が配置する
# ビルトインスキルなので触らない。
link_codex_skills() {
    local src_root="$DOTFILES_DIR/.codex/skills"
    local dst_root="$HOME/.codex/skills"

    [[ -d "$src_root" ]] || { warn "$src_root が無いため Codex skills リンクをスキップ"; return; }
    mkdir -p "$dst_root"

    local skill_dir name
    for skill_dir in "$src_root"/*/; do
        [[ -d "$skill_dir" ]] || continue
        name="$(basename "$skill_dir")"
        # Codex 標準スキル領域は除外（.system 以外も将来増える可能性があるので . 始まりは全除外）
        [[ "$name" == .* ]] && continue
        make_symlink "$dst_root/$name" "$src_root/$name" >/dev/null || true
    done
}
