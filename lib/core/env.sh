# shellcheck shell=bash
# dotfiles .env の存在チェック。DOTFILES_DIR に依存。

# ------------------------------------------------------------------
# ~/dotfiles/.env 存在チェック
# ------------------------------------------------------------------
check_env() {
    if [[ -f "$DOTFILES_DIR/.env" ]]; then
        log "~/dotfiles/.env 確認 OK"
        return
    fi

    err "~/dotfiles/.env が存在しません"
    err ""
    err "セットアップ前に以下を実施してください:"
    err "  1. cp $DOTFILES_DIR/.env.example $DOTFILES_DIR/.env"
    err "  2. \$EDITOR $DOTFILES_DIR/.env  # API キー等を記入"
    err "  3. ./install.sh を再実行"
    exit 1
}
