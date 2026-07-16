# shellcheck shell=bash
#
# AI ツールの読み込み口。
# 各ツールの install/update 実体は lib/tools/<tool>.sh に分割する。

# shellcheck source=lib/tools/claude.sh
. "$DOTFILES_DIR/lib/tools/claude.sh"
# shellcheck source=lib/tools/codex.sh
. "$DOTFILES_DIR/lib/tools/codex.sh"
# shellcheck source=lib/tools/gemini.sh
. "$DOTFILES_DIR/lib/tools/gemini.sh"
# shellcheck source=lib/tools/fugu.sh
. "$DOTFILES_DIR/lib/tools/fugu.sh"
# shellcheck source=lib/tools/herdr.sh
. "$DOTFILES_DIR/lib/tools/herdr.sh"
