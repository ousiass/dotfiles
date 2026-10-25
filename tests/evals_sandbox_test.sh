#!/usr/bin/env bash
# evals/sandbox/（eval 専用の隔離フォルダ）の回帰テスト。モデルも GitHub も呼ばない。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/evals_sandbox_test.sh
#
# 確かめること:
#   1. init.sh が隔離フォルダを作り、doctor.sh が通る（HOME・設定ディレクトリがすべて隔離フォルダの下、リンクが解決できる）
#   2. 隔離フォルダの中で動かしても、呼び出し元の HOME・設定ディレクトリに何も書かない
#   3. ユーザーの領域（~/.claude など）や、目印の無い既存フォルダには作らない
#   4. トークンの置き場（EVAL_GH_TOKEN / gh-token）が GH_TOKEN になり、API キーは外れる
#   5. seed.sh --plan が、ネットワークに出ずに、タスクセットが要る ref と Issue を並べる
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$DOTFILES_DIR/evals/sandbox"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

check_eq() {
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then ok "$name"; else ng "$name (期待 $want / 実際 $got)"; fi
}

check_match() {
    local name="$1" pattern="$2" text="$3"
    if [[ "$text" == *"$pattern"* ]]; then ok "$name"; else ng "$name ('$pattern' が無い: $text)"; fi
}

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# 呼び出し元の HOME は使い捨てにして、init.sh / with-env がそこへ書かないことを見る
export HOME="$tmp/callerhome"
mkdir -p "$HOME"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GH_TOKEN GITHUB_TOKEN EVAL_GH_TOKEN ANTHROPIC_API_KEY

# 試験対象の dotfiles は、いま作業しているこのリポジトリの HEAD（コミット済みの内容）
root="$tmp/sandbox"
out="$("$SANDBOX/init.sh" --root "$root" --dotfiles-url "$DOTFILES_DIR" --ref HEAD 2>&1)"
rc=$?
check_eq "init.sh: 成功する" 0 "$rc"
[[ "$rc" -eq 0 ]] || printf '%s\n' "$out"
check_eq "init.sh: 目印ができる" 1 "$([[ -f "$root/.eval-sandbox" ]] && echo 1 || echo 0)"
check_eq "init.sh: with-env が実行できる" 1 "$([[ -x "$root/with-env" ]] && echo 1 || echo 0)"
check_eq "init.sh: MCP の設定を置かない" 0 "$(find "$root/home" \( -name 'mcp.json' -o -name '.mcp.json' \) | wc -l | tr -d ' ')"
check_eq "init.sh: settings.json にテレメトリの env が無い" 0 "$(jq '(.env // {}) | keys | map(select(test("TELEMETRY|OTEL"))) | length' "$root/home/.claude/settings.json")"

# 2 回目も同じ結果（壊れない）
"$SANDBOX/init.sh" --root "$root" --dotfiles-url "$DOTFILES_DIR" --ref HEAD >/dev/null 2>&1
check_eq "init.sh: 2 回目も成功する" 0 "$?"

# --- 隔離フォルダの中 ------------------------------------------------------------------
doc="$("$root/with-env" "$root/dotfiles/evals/sandbox/doctor.sh" 2>&1)"
rc=$?
check_eq "doctor.sh: 通る" 0 "$rc"
[[ "$rc" -eq 0 ]] || printf '%s\n' "$doc"
# 出力の NG 行は、色つきの「NG」で始まる（mktemp のパスに NG が入っても拾わない）
check_eq "doctor.sh: NG が無い" 0 "$(printf '%s\n' "$doc" | grep -c $'^\033\\[1;31mNG')"

envdump="$(ANTHROPIC_API_KEY=sk-test SSH_AUTH_SOCK=/tmp/agent EVAL_GH_TOKEN=tok-env "$root/with-env" env)"
check_match "with-env: HOME が隔離フォルダ" "HOME=$root/home" "$envdump"
check_match "with-env: CLAUDE_CONFIG_DIR が隔離フォルダ" "CLAUDE_CONFIG_DIR=$root/home/.claude" "$envdump"
check_match "with-env: PI_CODING_AGENT_DIR が隔離フォルダ" "PI_CODING_AGENT_DIR=$root/home/.omp/agent" "$envdump"
check_match "with-env: EVAL_GH_TOKEN が GH_TOKEN になる" "GH_TOKEN=tok-env" "$envdump"
check_eq "with-env: EVAL_GH_TOKEN は残らない" 0 "$(printf '%s\n' "$envdump" | grep -c '^EVAL_GH_TOKEN=')"
check_eq "with-env: ANTHROPIC_API_KEY は外れる" 0 "$(printf '%s\n' "$envdump" | grep -c '^ANTHROPIC_API_KEY=')"
check_eq "with-env: SSH_AUTH_SOCK は外れる" 0 "$(printf '%s\n' "$envdump" | grep -c '^SSH_AUTH_SOCK=')"

printf 'tok-file\n' >"$root/gh-token"
chmod 600 "$root/gh-token"
check_match "with-env: gh-token ファイルが GH_TOKEN になる" "GH_TOKEN=tok-file" "$("$root/with-env" env)"
check_match "with-env: 環境変数がファイルより優先" "GH_TOKEN=tok-env" "$(EVAL_GH_TOKEN=tok-env "$root/with-env" env)"
rm -f "$root/gh-token"

# 隔離フォルダの外（呼び出し元の HOME）には何も書かれていない
check_eq "呼び出し元の HOME に何も作られていない" 0 "$(find "$HOME" -mindepth 1 | wc -l | tr -d ' ')"

# --- 作ってはいけない場所 ------------------------------------------------------------------
for bad in "$HOME" "$HOME/.claude/x" "$HOME/.omp/agent/x" "$HOME/dotfiles/x"; do
    "$SANDBOX/init.sh" --root "$bad" --dotfiles-url "$DOTFILES_DIR" --ref HEAD >/dev/null 2>&1
    check_eq "init.sh: ユーザーの領域には作らない (${bad#"$tmp"/})" 1 "$?"
done
mkdir -p "$tmp/occupied"
echo keep >"$tmp/occupied/file"
"$SANDBOX/init.sh" --root "$tmp/occupied" --dotfiles-url "$DOTFILES_DIR" --ref HEAD >/dev/null 2>&1
check_eq "init.sh: 目印の無い非空フォルダには作らない" 1 "$?"
check_eq "init.sh: 既存の中身を触らない" "keep" "$(cat "$tmp/occupied/file")"
"$SANDBOX/init.sh" --root relative/path --dotfiles-url "$DOTFILES_DIR" --ref HEAD >/dev/null 2>&1
check_eq "init.sh: 相対パスは拒否する" 1 "$?"
"$SANDBOX/init.sh" --root "$tmp/other" --dotfiles-url "$DOTFILES_DIR" --ref no-such-ref >/dev/null 2>&1
check_eq "init.sh: 存在しない ref は失敗する" 1 "$?"

# --- seed.sh --plan（ネットワークに出ない） ----------------------------------------------------
plan="$("$SANDBOX/seed.sh" --plan --repo example/none 2>&1)"
check_eq "seed.sh --plan: 成功する" 0 "$?"
n_issues="$(jq -s '[.[].issues[]?] | length' "$DOTFILES_DIR/evals/tasks.jsonl")"
check_match "seed.sh --plan: Issue の件数がタスクセットと一致する" "Issue: ${n_issues} 件" "$plan"
check_match "seed.sh --plan: refine のブランチを入れる" "eval/refine-defect/feat/wip" "$plan"
check_match "seed.sh --plan: シナリオの main を入れる" "eval/docs-typo/main" "$plan"

exit "$fail"
