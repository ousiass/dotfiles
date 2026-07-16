# shellcheck shell=bash
#
# install.sh / update.sh 共通のモジュール読み込み。
# エントリポイント側で DOTFILES_DIR を定義してから source する。

if [[ -z "${DOTFILES_DIR:-}" ]]; then
    printf '\033[1;31m[error]\033[0m DOTFILES_DIR is not set\n' >&2
    return 1 2>/dev/null || exit 1
fi

# common.sh は log/warn/err/make_symlink などを提供するため最初に読み込む。
# shellcheck source=lib/common.sh
. "$DOTFILES_DIR/lib/common.sh"
# shellcheck source=lib/install_lang.sh
. "$DOTFILES_DIR/lib/install_lang.sh"
# shellcheck source=lib/install_ai.sh
. "$DOTFILES_DIR/lib/install_ai.sh"
# shellcheck source=lib/install_devtools.sh
. "$DOTFILES_DIR/lib/install_devtools.sh"
# shellcheck source=lib/install_skills.sh
. "$DOTFILES_DIR/lib/install_skills.sh"
# shellcheck source=lib/setup_shell.sh
. "$DOTFILES_DIR/lib/setup_shell.sh"
