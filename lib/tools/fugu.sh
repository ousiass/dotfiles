# shellcheck shell=bash
# Fugu installer/updater. common.sh の log/warn と DOTFILES_DIR に依存。

install_fugu() {
    sync_fugu_codex
}
update_fugu() {
    sync_fugu_codex
}
