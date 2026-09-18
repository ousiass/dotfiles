#!/usr/bin/env bash
# cleanup.sh の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/cleanup_test.sh
#
# 背景: キャッシュ類を NVMe へ移したことで ~/.cache/go-build や
# ~/.claude/projects がシンボリックリンクになった。du と find は
# 引数がシンボリックリンクでも既定では辿らないため、掃除が黙って
# 空振りしていた。その再発を防ぐ。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../cleanup.sh
. "$DOTFILES_DIR/cleanup.sh"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

check_eq() {
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then ok "$name"; else ng "$name (期待 $want / 実際 $got)"; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# --- dir_size_gb がシンボリックリンク越しでも実サイズを返すこと ---------------
# du -sb は見かけのサイズを数えるので、スパースファイルで一瞬で作れる。
mkdir -p "$tmp/real"
truncate -s 200M "$tmp/real/big"
ln -s "$tmp/real" "$tmp/link"

check_eq "dir_size_gb: 実ディレクトリ"       "0.2" "$(dir_size_gb "$tmp/real")"
check_eq "dir_size_gb: シンボリックリンク"   "0.2" "$(dir_size_gb "$tmp/link")"

# --- clean_claude がシンボリックリンク越しの projects を退避できること --------
mkdir -p "$tmp/store/proj/subagents" "$tmp/home/.claude" "$tmp/archive"
echo dummy > "$tmp/store/proj/subagents/old.jsonl"
touch -d '30 days ago' "$tmp/store/proj/subagents/old.jsonl"
ln -s "$tmp/store" "$tmp/home/.claude/projects"

HOME="$tmp/home" ARCHIVE_DIR="$tmp/archive/subagents" clean_claude >/dev/null 2>&1

if [[ -f "$tmp/archive/subagents/proj/subagents/old.jsonl" ]]; then
    ok "clean_claude: シンボリックリンク越しに退避できる"
else
    ng "clean_claude: シンボリックリンク越しに退避できる (退避されなかった)"
fi

exit "$fail"
