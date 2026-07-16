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
# Global gitignore のセットアップ
#
# ~/.gitignore を dotfiles の .gitignore へ symlink し、
# git config --global core.excludesfile で参照させる。
# これでマシン上の全 git リポジトリで .claude/ や .sweep/ などが
# デフォルトで ignore される。dotfiles 更新時は symlink 経由で自動反映。
# ------------------------------------------------------------------
setup_global_gitignore() {
    if [[ ! -f "$DOTFILES_DIR/.gitignore" ]]; then
        warn "$DOTFILES_DIR/.gitignore が存在しないため global gitignore セットアップをスキップ"
        return
    fi

    link_home_file .gitignore

    local dst="$HOME/.gitignore"
    local current
    current="$(git config --global --get core.excludesfile 2>/dev/null || true)"
    if [[ "$current" != "$dst" ]]; then
        git config --global core.excludesfile "$dst"
        log "git config --global core.excludesfile = $dst"
    fi
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

    log "デフォルトシェルを fish に変更 (chsh -s $fish_path)"
    chsh -s "$fish_path" || warn "chsh に失敗（フォールバックを試行）"

    # macOS の chsh は Directory Service に反映されず silently no-op で
    # exit 0 を返すケースがある（Issue #3）。実際に反映されたか再取得して
    # 検証し、未反映なら sudo で USER を明示指定して再試行する。
    current_shell="$(get_login_shell)"
    if [[ "$current_shell" != "$fish_path" ]]; then
        warn "chsh 後もデフォルトシェルが '$current_shell' のまま。sudo chsh でリトライ"
        sudo chsh -s "$fish_path" "$USER" \
            || warn "sudo chsh に失敗"
        current_shell="$(get_login_shell)"
    fi

    if [[ "$current_shell" == "$fish_path" ]]; then
        log "デフォルトシェルを fish に変更完了"
        warn "→ 再ログインで反映されます"
    else
        warn "デフォルトシェルの変更に失敗しました (現在: $current_shell)"
        warn "  → 手動で 'chsh -s $fish_path' または 'sudo chsh -s $fish_path $USER' を実行"
        warn "  → Terminal.app / iTerm2 の '起動時に開くシェル' 設定が固定になっている場合はアプリ側も確認"
    fi
}
