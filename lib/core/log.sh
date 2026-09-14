# shellcheck shell=bash
# ログ出力ヘルパー。
#
# LOG_TAG で行頭のタグを差し替えられる（既定は install）。
# 例: LOG_TAG=cleanup を設定すると [cleanup] と出る。

: "${LOG_TAG:=install}"

log()  { printf '\033[1;34m[%s]\033[0m %s\n' "$LOG_TAG" "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }
