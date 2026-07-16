# shellcheck shell=bash
# symlink ヘルパー。CONFIG_DIR / DOTFILES_DIR / TIMESTAMP に依存。

# ------------------------------------------------------------------
# 共通シンボリックリンクヘルパー
# ------------------------------------------------------------------
make_symlink() {
    local target="$1"
    local source="$2"

    mkdir -p "$(dirname "$target")"

    if [[ -L "$target" ]]; then
        local current
        current="$(readlink "$target")"
        if [[ "$current" == "$source" ]]; then
            log "$target は既に正しくリンク済み"
            return 1
        fi
        log "$target の既存リンク ($current) を削除"
        rm "$target"
    elif [[ -e "$target" ]]; then
        local backup="$target.bak.$TIMESTAMP"
        log "既存の $target を $backup にバックアップ"
        mv "$target" "$backup"
    fi

    ln -s "$source" "$target"
    log "$target -> $source"
    return 0
}

link_config() {
    local name="$1"
    make_symlink "$CONFIG_DIR/$name" "$DOTFILES_DIR/$name" >/dev/null || true
}

link_home_file() {
    local target_name="$1"
    local source_path="${2:-$1}"
    make_symlink "$HOME/$target_name" "$DOTFILES_DIR/$source_path" >/dev/null || true
}
