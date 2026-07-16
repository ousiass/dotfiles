# shellcheck shell=bash
# ~/.claude の symlink 化。DOTFILES_DIR / TIMESTAMP に依存。

# ------------------------------------------------------------------
# ~/.claude のシンボリックリンク化（ランタイムデータ保全付き）
# ------------------------------------------------------------------
link_claude() {
    local target="$HOME/.claude"
    local source="$DOTFILES_DIR/.claude"

    if [[ -L "$target" ]] && [[ "$(readlink "$target")" == "$source" ]]; then
        log "$target は既に正しくリンク済み"
        return
    fi

    if [[ -L "$target" ]]; then
        log "$target の既存リンクを削除"
        rm "$target"
        ln -s "$source" "$target"
        log "$target -> $source"
        return
    fi

    if [[ -d "$target" ]]; then
        local backup="$target.bak.$TIMESTAMP"
        log "既存の $target を $backup にバックアップ"
        mv "$target" "$backup"
        ln -s "$source" "$target"
        log "$target -> $source"

        log "ランタイムデータを移行（既存は保護）"
        rsync -a --ignore-existing "$backup/" "$source/"
        warn "→ $backup は確認後 \`rm -rf\` で削除可"
        return
    fi

    ln -s "$source" "$target"
    log "$target -> $source"
}
