# shellcheck shell=bash
#
# 言語ツールの読み込み口。
# 各ツールの install/update 実体は lib/tools/<tool>.sh に分割する。

# shellcheck source=lib/tools/uv.sh
. "$DOTFILES_DIR/lib/tools/uv.sh"
# shellcheck source=lib/tools/bun.sh
. "$DOTFILES_DIR/lib/tools/bun.sh"
# shellcheck source=lib/tools/rustup.sh
. "$DOTFILES_DIR/lib/tools/rustup.sh"
# shellcheck source=lib/tools/fnm.sh
. "$DOTFILES_DIR/lib/tools/fnm.sh"
# shellcheck source=lib/tools/go.sh
. "$DOTFILES_DIR/lib/tools/go.sh"
# shellcheck source=lib/tools/node_lts.sh
. "$DOTFILES_DIR/lib/tools/node_lts.sh"
