# shellcheck shell=bash
#
# シェル周りのセットアップ:
#   - ~/.profile への dotfiles paths セクション挿入
#   - fisher / fish プラグイン
#   - nvim プラグイン同期
#   - fish をデフォルトシェルに

# ------------------------------------------------------------------
# ~/.profile に shell/paths.sh の source 行を冪等に挿入
#
# fish 側は fish/conf.d/paths.fish が起動時に PATH を設定するので、対応する
# bash login shell (~/.profile) からも shell/paths.sh を読み込ませる。
# これで bash interactive / non-interactive (Claude Code の Bash ツール等) /
# IDE 経由の起動でも、go や fnm などのツールを発見できる状態になる。
# ------------------------------------------------------------------
setup_profile_paths() {
    local profile="$HOME/.profile"
    local marker_begin="# >>> dotfiles paths >>>"
    local marker_end="# <<< dotfiles paths <<<"

    if [[ ! -f "$profile" ]]; then
        log "$profile を新規作成"
        : > "$profile"
    fi

    # 既存マーカーブロックがあれば一旦削除（GNU/BSD sed 両対応で -i.bak を使用）
    if grep -qF "$marker_begin" "$profile"; then
        sed -i.bak "/$marker_begin/,/$marker_end/d" "$profile"
        rm -f "$profile.bak"
    fi

    # 末尾にマーカー付きで追記
    cat >> "$profile" <<EOF

$marker_begin
# 自動生成 (install.sh): dotfiles/shell/paths.sh を source して PATH を統一する。
# fish/conf.d/paths.fish と同じパス集合を bash login shell でも有効にする。
if [ -f "$DOTFILES_DIR/shell/paths.sh" ]; then
    . "$DOTFILES_DIR/shell/paths.sh"
fi
$marker_end
EOF
    log "$profile に dotfiles paths セクションを反映"
}

# ------------------------------------------------------------------
# fisher と fish プラグイン
# ------------------------------------------------------------------
install_fisher() {
    if ! command -v fish >/dev/null 2>&1; then
        warn "fish が見つからないため fisher セットアップをスキップ"
        return
    fi

    log "fisher と fish プラグインをセットアップ"
    fish -c '
        if not functions -q fisher
            curl -sL https://raw.githubusercontent.com/jorgebucaran/fisher/main/functions/fisher.fish | source
            fisher install jorgebucaran/fisher
        end
        fisher update
    ' || warn "fisher のセットアップで問題あり。手動で 'fisher update' を実行してください"
}

update_fisher() {
    if ! command -v fish >/dev/null 2>&1; then
        warn "fish が無いため fisher の update をスキップ"
        return
    fi
    log "fisher プラグインを更新 (fisher update)"
    fish -c 'fisher update' || warn "fisher の update に失敗"
}

# ------------------------------------------------------------------
# nvim プラグインの同期
# ------------------------------------------------------------------
sync_nvim_plugins() {
    if ! command -v nvim >/dev/null 2>&1; then
        warn "nvim が見つからないためプラグイン同期をスキップ"
        return
    fi
    log "nvim プラグインを同期 (lazy.nvim restore: lockfile に合わせて固定)"
    nvim --headless "+Lazy! restore" +qa || warn "lazy.nvim の同期で問題あり（初回は無視可）"
}

update_nvim_plugins() {
    if ! command -v nvim >/dev/null 2>&1; then
        warn "nvim が無いためプラグイン update をスキップ"
        return
    fi
    log "nvim プラグインを最新へ (lazy.nvim sync)"
    nvim --headless "+Lazy! sync" +qa || warn "lazy.nvim の update に失敗"
}

# ------------------------------------------------------------------
# fish をデフォルトシェルに
# ------------------------------------------------------------------
get_login_shell() {
    if [[ "$OS" == "mac" ]]; then
        dscl . -read "/Users/$USER" UserShell 2>/dev/null | awk '{print $2}'
    else
        getent passwd "$USER" | awk -F: '{print $NF}'
    fi
}

set_default_shell() {
    local fish_path
    fish_path="$(command -v fish || true)"
    if [[ -z "$fish_path" ]]; then
        warn "fish が見つからないためデフォルトシェル変更をスキップ"
        return
    fi

    if ! grep -qx "$fish_path" /etc/shells 2>/dev/null; then
        log "$fish_path を /etc/shells に追加"
        echo "$fish_path" | sudo tee -a /etc/shells >/dev/null
    fi

    local current_shell
    current_shell="$(get_login_shell)"
    if [[ "$current_shell" == "$fish_path" ]]; then
        log "デフォルトシェルは既に fish"
        return
    fi

    log "デフォルトシェルを fish に変更"
    chsh -s "$fish_path" || warn "chsh に失敗しました（手動で実行してください）"
    warn "→ 再ログインで反映されます"
}
