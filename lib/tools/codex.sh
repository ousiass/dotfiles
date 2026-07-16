# shellcheck shell=bash
# Codex CLI / Fugu sync aliases. common.sh の log/warn に依存。

install_codex() {
    install_codex_cli "$@"
}
install_codex_fugu() {
    install_fugu "$@"
}
install_codex_cli() {
    local fugu_target current
    fugu_target="$(fugu_codex_target || true)"

    if [[ -n "$fugu_target" ]]; then
        current="$(codex_cli_version || true)"
        if [[ "$current" == "$fugu_target" ]]; then
            log "Codex CLI は Fugu target と整合済み ($current)"
            return
        fi
        log "Codex CLI を Fugu target に自動整合 (${current:-未インストール} -> $fugu_target)"
        sync_fugu_codex
        return
    fi

    if command -v codex >/dev/null 2>&1; then
        current="$(codex_cli_version || true)"
        log "Codex CLI は既にインストール済み${current:+ ($current)}"
        return
    fi

    if ! command -v bun >/dev/null 2>&1; then
        warn "bun が見つからないため Codex CLI インストールをスキップ"
        return
    fi

    log "Codex CLI をインストール (bun -g @openai/codex)"
    bun install -g @openai/codex
}

codex_session_active() {
    [[ -n "${CODEX_CI:-}" || -n "${CODEX_THREAD_ID:-}" ]]
}

codex_cli_version() {
    codex --version 2>/dev/null | grep -oE 'codex-cli[[:space:]]+[0-9][0-9.]*' | head -n1 | awk '{print $2}'
}

load_fugu_env() {
    local env_file="$DOTFILES_DIR/.env"
    if [[ -z "${SAKANA_API_KEY:-}" && -f "$env_file" ]]; then
        set -a
        # shellcheck disable=SC1090
        . "$env_file" || true
        set +a
    fi
}

fugu_installer_path() {
    local bundle_file repo_dir
    bundle_file="$(fugu_bundle_file || true)"
    if [[ -n "$bundle_file" ]]; then
        repo_dir="$(dirname "$(dirname "$bundle_file")")"
        if [[ -x "$repo_dir/scripts/install.sh" ]]; then
            printf '%s/scripts/install.sh' "$repo_dir"
            return
        fi
    fi

    if [[ -x "$HOME/.fugu/scripts/install.sh" ]]; then
        printf '%s/.fugu/scripts/install.sh' "$HOME"
    fi
}
sync_fugu_codex() {
    load_fugu_env

    if codex_session_active; then
        warn "Codex/Fugu セッション中のため Codex/Fugu 自動整合をスキップ"
        warn "  → このセッションを終了してから './install.sh fugu' または './update.sh codex_fugu' を実行してください"
        return
    fi

    local installer
    installer="$(fugu_installer_path || true)"
    if [[ -n "$installer" ]]; then
        log "Fugu installer で Codex と codex-fugu を自動整合 (--yes --force)"
        FUGU_ASSUME_YES=1 FUGU_FORCE=1 "$installer" --yes --force \
            || warn "Fugu/Codex の自動整合に失敗"
        return
    fi

    if [[ -z "${SAKANA_API_KEY:-}" ]]; then
        warn "SAKANA_API_KEY が未設定のため Fugu インストーラ取得をスキップ"
        warn "  → $DOTFILES_DIR/.env に SAKANA_API_KEY=... を追加して再実行"
        return
    fi

    log "Fugu installer を取得して Codex と codex-fugu を自動整合 (--yes --force)"
    FUGU_ASSUME_YES=1 FUGU_FORCE=1 bash -c 'curl -fsSL https://sakana.ai/fugu/install | bash' \
        || warn "Fugu/Codex の自動整合に失敗"
}

fugu_state_file() {
    printf '%s/.fugu/state' "${CODEX_HOME:-$HOME/.codex}"
}

fugu_bundle_file() {
    local state_file repo_dir
    state_file="$(fugu_state_file)"
    if [[ -f "$state_file" ]]; then
        repo_dir="$(sed -n 's/^repo_dir=//p' "$state_file" | tail -n1)"
        if [[ -n "$repo_dir" && -f "$repo_dir/configs/bundle.sh" ]]; then
            printf '%s/configs/bundle.sh' "$repo_dir"
            return
        fi
    fi

    if [[ -f "$HOME/.fugu/configs/bundle.sh" ]]; then
        printf '%s/.fugu/configs/bundle.sh' "$HOME"
    fi
}

fugu_codex_target() {
    local state_file bundle_file target
    state_file="$(fugu_state_file)"
    if [[ -f "$state_file" ]]; then
        target="$(sed -n 's/^deployed_target=//p' "$state_file" | tail -n1)"
        if [[ -n "$target" ]]; then
            printf '%s' "$target"
            return
        fi
    fi

    bundle_file="$(fugu_bundle_file || true)"
    if [[ -n "$bundle_file" && -f "$bundle_file" ]]; then
        awk -F= '/^BUNDLE_CODEX_VERSION=/ { gsub(/"/, "", $2); print $2; exit }' "$bundle_file"
    fi
}
update_codex() {
    update_codex_cli "$@"
}
update_codex_fugu() {
    update_fugu "$@"
}
update_codex_cli() {
    local fugu_target current
    fugu_target="$(fugu_codex_target || true)"

    if [[ -n "$fugu_target" ]]; then
        current="$(codex_cli_version || true)"
        if [[ "$current" == "$fugu_target" ]]; then
            log "Codex CLI は Fugu target と整合済み ($current)"
            return
        fi
        log "Codex CLI を Fugu target に自動整合 (${current:-未インストール} -> $fugu_target)"
        sync_fugu_codex
        return
    fi

    if ! command -v codex >/dev/null 2>&1; then
        warn "codex が無いため update をスキップ"
        return
    fi

    if codex_session_active; then
        warn "Codex セッション中のため codex update をスキップ"
        warn "  → Codex を終了してから 'codex update' を手動実行してください"
        return
    fi

    # Fugu 非管理の通常 Codex では、現在有効な `codex` 自身に更新させる。
    if codex help update >/dev/null 2>&1; then
        log "Codex CLI を更新 (codex update)"
        codex update || warn "codex update に失敗"
        return
    fi

    if command -v bun >/dev/null 2>&1; then
        log "Codex CLI を更新 (bun update -g @openai/codex)"
        bun update -g @openai/codex || warn "codex の update に失敗"
    elif command -v npm >/dev/null 2>&1; then
        log "Codex CLI を更新 (npm install -g @openai/codex)"
        npm install -g @openai/codex || warn "codex の update に失敗"
    else
        warn "bun/npm が無いため codex の update をスキップ"
    fi
}
