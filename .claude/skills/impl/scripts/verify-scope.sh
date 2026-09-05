#!/usr/bin/env bash
# verify-scope.sh — impl のスコープ完了ゲート（フェーズ 2-6）
#
# 未コミットの変更に対して以下を機械的に検証する:
#   1. 追加行に未実装パターン（TODO / NotImplementedError / ダミーアサーション等）が無いこと
#   2. fix 型スコープならテストファイルが追加・変更されていること（fail-first の痕跡）
#   3. テストコマンドが exit 0 で終わること
#   4. lint コマンドが exit 0 で終わること
#
# 使い方:
#   verify-scope.sh --type <fix|feat|refactor|docs|test|chore> [--test-cmd CMD] [--lint-cmd CMD]
#   verify-scope.sh --profile-path   # repo プロファイルの保存先パスを表示して終了
#
# --test-cmd / --lint-cmd を省略した場合は repo プロファイルから読む。
# 空文字を明示的に渡す（--test-cmd ""）とその項目を SKIP 扱いにする。
#
# 終了コード: 0 = FAIL なし / 1 = 1 つ以上 FAIL / 2 = 使い方の誤り

set -uo pipefail

die() { printf 'verify-scope: %s\n' "$1" >&2; exit 2; }

# --- repo プロファイルのパス解決（このスクリプトが単一の正とする） ---------
profile_path() {
  local common_dir key
  common_dir=$(git rev-parse --path-format=absolute --git-common-dir 2>/dev/null) \
    || die 'git リポジトリの外で実行されている'
  key=$(printf '%s' "$common_dir" | sha256sum | cut -c1-16)
  printf '%s/.claude/cache/repo-profile/%s.json' "$HOME" "$key"
}

[ "${1:-}" = "--profile-path" ] && { profile_path; exit 0; }

scope_type=""
test_cmd=""; test_cmd_set=0
lint_cmd=""; lint_cmd_set=0

while [ $# -gt 0 ]; do
  case "$1" in
    --type)     scope_type="${2:-}"; shift 2 ;;
    --test-cmd) test_cmd="${2:-}"; test_cmd_set=1; shift 2 ;;
    --lint-cmd) lint_cmd="${2:-}"; lint_cmd_set=1; shift 2 ;;
    *) die "不明な引数: $1" ;;
  esac
done
[ -n "$scope_type" ] || die '--type は必須（fix|feat|refactor|docs|test|chore）'

root=$(git rev-parse --show-toplevel 2>/dev/null) || die 'git リポジトリの外で実行されている'
cd "$root" || die "cd に失敗: $root"

# プロファイルからコマンドを補完する（明示指定があればそちらを優先）
prof=$(profile_path)
if [ -f "$prof" ] && command -v jq >/dev/null 2>&1; then
  [ "$test_cmd_set" -eq 0 ] && test_cmd=$(jq -r '.test_cmd // ""' "$prof")
  [ "$lint_cmd_set" -eq 0 ] && lint_cmd=$(jq -r '.lint_cmd // ""' "$prof")
fi

fails=0
warns=0
report=""
add() { report="${report}$1"$'\n'; }
pass() { add "  PASS  $1"; }
skip() { add "  SKIP  $1"; }
warn() { add "  WARN  $1"; warns=$((warns + 1)); }
fail() { add "  FAIL  $1"; fails=$((fails + 1)); }

git_q() { git -c core.quotePath=false "$@"; }

# --- 変更ファイルの一覧（tracked の変更 + untracked の新規） -----------------
changed_files=$(
  { git_q diff HEAD --name-only 2>/dev/null
    git_q ls-files --others --exclude-standard 2>/dev/null
  } | sort -u
)

if [ -z "$changed_files" ]; then
  printf '未コミットの変更がありません。コミット対象が無い状態でゲートを実行しています。\n' >&2
  exit 1
fi

# --- 追加行を "file:line: content" 形式で列挙 -------------------------------
# tracked: git diff -U0 のハンクヘッダから新ファイル側の行番号を復元する
# untracked: 全行が追加行なので grep -n をそのまま使う
added_lines() {
  local f
  while IFS= read -r f; do
    [ -f "$f" ] || continue
    grep -Iq . "$f" 2>/dev/null || continue   # バイナリは除外
    if git_q ls-files --error-unmatch "$f" >/dev/null 2>&1; then
      git_q diff HEAD --unified=0 --no-color -- "$f" 2>/dev/null \
        | grep -v '^+++' \
        | awk -v f="$f" '
            /^@@/ { if (match($0, /\+[0-9]+/)) n = substr($0, RSTART + 1, RLENGTH - 1); next }
            /^\+/ { print f ":" n ": " substr($0, 2); n++ }
          '
    else
      grep -n '' "$f" 2>/dev/null | sed "s|^\([0-9]*\):|$f:\1: |"
    fi
  done <<< "$changed_files"
}

added=$(added_lines)

# 意図的に残す行は `verify-scope: allow` を同じ行に書いて除外する
added=$(printf '%s\n' "$added" | grep -v 'verify-scope: allow')

# --- 1. 未実装パターン ------------------------------------------------------
unimpl_re='TODO|FIXME|NotImplementedError|NotImplemented[^a-zA-Z]|[Nn]ot implemented|todo!\(|unimplemented!\(|expect\(true\)\.toBe\(true\)|assertTrue\(True\)|assert True$|assert\(true\)'
hits=$(printf '%s\n' "$added" | grep -nE "$unimpl_re" | cut -d: -f2- || true)
if [ -n "$hits" ]; then
  fail "追加行に未実装パターンがあります:"
  add "$(printf '%s\n' "$hits" | head -20 | sed 's/^/          /')"
else
  pass '未実装パターンなし'
fi

# スキップされたテストは落とさず警告に留める（意図的なスキップがあり得るため）
skip_re='it\.skip\(|test\.skip\(|describe\.skip\(|xit\(|xdescribe\(|@pytest\.mark\.skip|t\.Skip\(|#\[ignore\]'
skips=$(printf '%s\n' "$added" | grep -nE "$skip_re" | cut -d: -f2- || true)
[ -n "$skips" ] && warn "スキップされたテストが追加されています:"$'\n'"$(printf '%s\n' "$skips" | head -10 | sed 's/^/          /')"

# --- 2. fix 型の回帰テスト --------------------------------------------------
test_path_re='(^|/)(tests?|__tests__|spec|specs)/|[._-](test|spec)\.[A-Za-z]+$|(^|/)test_[^/]*\.py$|_test\.go$|Test[A-Za-z]*\.java$'
if [ "$scope_type" = "fix" ]; then
  if printf '%s\n' "$changed_files" | grep -qE "$test_path_re"; then
    pass 'fix 型: テストファイルの追加・変更あり'
  else
    fail 'fix 型スコープなのにテストファイルが 1 件も変更されていません（CLAUDE.md の回帰テスト必須規約に違反）'
  fi
else
  skip "fix 型以外（$scope_type）のため回帰テスト検査は対象外"
fi

# --- 3. テスト --------------------------------------------------------------
test_log=$(mktemp); lint_log=$(mktemp)
trap 'rm -f "$test_log" "$lint_log"' EXIT

if [ -n "$test_cmd" ]; then
  if bash -c "$test_cmd" >"$test_log" 2>&1; then
    pass "テスト: $test_cmd"
  else
    fail "テストが失敗しました（$test_cmd）— 末尾 40 行:"
    add "$(tail -40 "$test_log" | sed 's/^/          /')"
  fi
else
  skip 'テストコマンド未設定（repo プロファイルの test_cmd が空）'
fi

# --- 4. lint ----------------------------------------------------------------
if [ -n "$lint_cmd" ]; then
  if bash -c "$lint_cmd" >"$lint_log" 2>&1; then
    pass "lint: $lint_cmd"
  else
    fail "lint が失敗しました（$lint_cmd）— 末尾 40 行:"
    add "$(tail -40 "$lint_log" | sed 's/^/          /')"
  fi
else
  skip 'lint コマンド未設定（repo プロファイルの lint_cmd が空）'
fi

# --- 結果 -------------------------------------------------------------------
printf '=== verify-scope (type=%s) ===\n' "$scope_type"
printf '%s' "$report"
if [ "$fails" -gt 0 ]; then
  printf -- '--- 結果: FAIL %d 件 / WARN %d 件 → コミット禁止 ---\n' "$fails" "$warns"
  exit 1
fi
printf -- '--- 結果: FAIL 0 件 / WARN %d 件 → コミット可 ---\n' "$warns"
exit 0
