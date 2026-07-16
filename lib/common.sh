# shellcheck shell=bash
#
# 共通ヘルパーの読み込み口。
# 実体は lib/core/*.sh に責務単位で分割する。

# shellcheck source=lib/core/log.sh
. "$DOTFILES_DIR/lib/core/log.sh"
# shellcheck source=lib/core/os.sh
. "$DOTFILES_DIR/lib/core/os.sh"
# shellcheck source=lib/core/env.sh
. "$DOTFILES_DIR/lib/core/env.sh"
# shellcheck source=lib/core/brew.sh
. "$DOTFILES_DIR/lib/core/brew.sh"
# shellcheck source=lib/core/packages.sh
. "$DOTFILES_DIR/lib/core/packages.sh"
# shellcheck source=lib/core/neovim.sh
. "$DOTFILES_DIR/lib/core/neovim.sh"
# shellcheck source=lib/core/link.sh
. "$DOTFILES_DIR/lib/core/link.sh"
# shellcheck source=lib/core/codex.sh
. "$DOTFILES_DIR/lib/core/codex.sh"
# shellcheck source=lib/core/claude.sh
. "$DOTFILES_DIR/lib/core/claude.sh"
