# shellcheck shell=bash
#
# 開発 CLI / 自作ツールの読み込み口。
# 各ツールの install/update 実体は lib/tools/<tool>.sh に分割する。

# shellcheck source=lib/tools/lazygit.sh
. "$DOTFILES_DIR/lib/tools/lazygit.sh"
# shellcheck source=lib/tools/gh.sh
. "$DOTFILES_DIR/lib/tools/gh.sh"
# shellcheck source=lib/tools/gcloud.sh
. "$DOTFILES_DIR/lib/tools/gcloud.sh"
# shellcheck source=lib/tools/cloudflared.sh
. "$DOTFILES_DIR/lib/tools/cloudflared.sh"
# shellcheck source=lib/tools/wrangler.sh
. "$DOTFILES_DIR/lib/tools/wrangler.sh"
# shellcheck source=lib/tools/netlify_cli.sh
. "$DOTFILES_DIR/lib/tools/netlify_cli.sh"
# shellcheck source=lib/tools/pm2.sh
. "$DOTFILES_DIR/lib/tools/pm2.sh"
# shellcheck source=lib/tools/moleport.sh
. "$DOTFILES_DIR/lib/tools/moleport.sh"
# shellcheck source=lib/tools/linterly.sh
. "$DOTFILES_DIR/lib/tools/linterly.sh"
