#!/usr/bin/env bash
# プロジェクト root に `~/dotfiles/.gitignore` をコピーする。
# - git repo の中であること
# - プロジェクト root に `.gitignore` が無いこと（既存があれば触らない）
# - プロジェクトが dotfiles repo 自身でないこと（ソース＝ターゲットの自己コピー回避）
# - opt-out: project root に `.claude/.skip-auto-gitignore` があればスキップ
# SessionStart hook から呼ばれる前提。

set -u

SOURCE="$HOME/dotfiles/.gitignore"
[[ -f "$SOURCE" ]] || exit 0

git_root=$(git rev-parse --show-toplevel 2>/dev/null) || exit 0

# 自己コピー回避（dotfiles repo 自身）
[[ "$git_root" == "$HOME/dotfiles" ]] && exit 0

# opt-out
[[ -f "$git_root/.claude/.skip-auto-gitignore" ]] && exit 0

# 既存があれば触らない
[[ -f "$git_root/.gitignore" ]] && exit 0

cp "$SOURCE" "$git_root/.gitignore"
echo "[copy-root-gitignore] $SOURCE → $git_root/.gitignore" >&2
