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

# $2 に yes/no で「そのディレクトリが残っていてほしいか」を書く。
check_dir() {
    local name="$1" want="$2" got=no
    [[ -d "$3" ]] && got=yes
    check_eq "$name" "$want" "$got"
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

# --- clean_gotmp が「古い残骸だけ」を消すこと --------------------------------
# go は正常終了時に $TMPDIR/go-build* を自分で消す。残っているのは kill された
# ビルドの跡なので消してよいが、実行中のビルドを巻き込んではいけない。
gotmp="$tmp/gotmp"
mkdir -p "$gotmp/go-build-old" "$gotmp/go-build-30h" "$gotmp/go-build-new" "$gotmp/keepme"
truncate -s 10M "$gotmp/go-build-old/a"
touch -d '2 days ago' "$gotmp/go-build-old"
# 30時間前。find の -mtime は日数を切り捨てるため +1 だと 48時間超しか消えない。
# GO_TMP_AGE_DAYS=1 と書いたら 24時間で消えること。
touch -d '30 hours ago' "$gotmp/go-build-30h"

TMPDIR="$gotmp" GO_TMP_AGE_DAYS=1 clean_gotmp >/dev/null 2>&1

check_dir "clean_gotmp: 古い残骸を消す"           no  "$gotmp/go-build-old"
check_dir "clean_gotmp: 24時間を過ぎたら消す"      no  "$gotmp/go-build-30h"
check_dir "clean_gotmp: 新しいものは残す"         yes "$gotmp/go-build-new"
check_dir "clean_gotmp: go-build 以外は触らない"  yes "$gotmp/keepme"

exit "$fail"
