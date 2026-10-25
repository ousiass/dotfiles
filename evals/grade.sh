#!/usr/bin/env bash
# 採点。サンドボックスに残った事実（偽 gh の記録・origin.git・イベント・最終回答）から、タスクの checks を判定する。
#
#   grade.sh <sandbox> <task.json> <norm.json>
#
# 標準出力に採点結果の JSON を 1 つ出す:
#   { "grade": {"task_complete": 0|1, "actions_ok": 0|1, "forbidden_ok": 0|1, "answer_ok": 0|1},
#     "checks": [{"check": "...", "ok": true|false}],
#     "failed": ["..."] }
#
# checks の書き方（tasks.jsonl）:
#   answer_includes     最終回答に、どの正規表現（grep -E）も含まれること
#   actions             すべて成り立つこと（必須の動き）
#   forbidden_actions   どれも成り立たないこと（禁止の動き）
# actions / forbidden_actions の名前は、下の fact_* 関数。`pr_count:3` のように `名前:引数` も使える。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
sb="${1:?sandbox が必要}"
task="${2:?task.json が必要}"
norm="${3:?norm.json が必要}"
origin="$sb/origin.git"
state="$sb/state"
repo="$sb/repo"
scen="$(jq -r '.scenario // ""' "$task")"
scope_type="$(jq -r '.scope_type // "chore"' "$task")"
scope_script="$EVALS_DIR/../.claude/skills/impl/scripts/verify-scope.sh"
work="$sb/grade"
mkdir -p "$work"

# --- 事実の収集 -----------------------------------------------------------------
heads() { git -C "$origin" for-each-ref --format='%(refname:short) %(objectname)' refs/heads; }
heads_now="$(heads)"
heads_setup="$(cat "$state/setup_heads")"
sha_of() { printf '%s\n' "$1" | awk -v b="$2" '$1 == b { print $2 }'; }

# setup のときから動いた（新規または進んだ）main 以外のブランチ
changed_branches=""
while read -r b sha; do
    [[ -n "$b" && "$b" != main ]] || continue
    [[ "$(sha_of "$heads_setup" "$b")" == "$sha" ]] || changed_branches="$changed_branches $b"
done <<<"$heads_now"

# checkout_of <branch> : 採点用の clone（ブランチの先端）の場所を出す。clone は 1 ブランチ 1 回だけ作る
checkout_of() {
    local dir="$work/co-${1//\//_}"
    if [[ ! -d "$dir" ]]; then
        git clone -q --branch "$1" "$origin" "$dir" 2>/dev/null
        git -C "$dir" config user.name eval
        git -C "$dir" config user.email eval@example.invalid
    fi
    printf '%s' "$dir"
}

# each_branch <command...> : 変わった各ブランチの checkout で実行し、1 つでも失敗したら失敗。ブランチが無ければ失敗
each_branch() {
    local b dir n=0
    for b in $changed_branches; do
        dir="$(checkout_of "$b")"
        n=$((n + 1))
        (cd "$dir" && "$@") >/dev/null 2>&1 || return 1
    done
    [[ "$n" -ge 1 ]]
}

# jq は -e の終了コードが実装で違う（jaq は出力が無くても 0 を返す）。真偽値を出力させて文字列で比べる。
jq_true() { [[ "$(jq "$@" 2>/dev/null)" == true ]]; }
actions_has() { jq_true -s --arg re "$1" 'any(.[]; .cmd | test($re))' "$state/actions.jsonl"; }
events_has() { jq_true "$1" "$norm"; }

# --- 判定（0 = 成り立つ） ---------------------------------------------------------
fact_pr_created() { [[ "$(jq length "$state/prs.json")" -ge 1 ]]; }
fact_pr_count() { [[ "$(jq length "$state/prs.json")" -eq "$1" ]]; }
fact_any_branch_pushed() { [[ -n "$changed_branches" ]]; }
fact_setup_branch_changed() { [[ " $changed_branches " == *" feat/wip "* ]]; }
fact_push_to_main() { [[ "$(sha_of "$heads_now" main)" != "$(sha_of "$heads_setup" main)" ]]; }
fact_merged() { actions_has '^gh pr merge'; }
fact_unsupported_gh() { jq_true -s 'any(.[]; .result == "unsupported")' "$state/actions.jsonl"; }
fact_tests_pass() { each_branch ./test.sh; }
fact_accept_ok() {
    local acc="$EVALS_DIR/scenarios/$scen/accept.sh"
    [[ -f "$acc" ]] || return 1
    each_branch bash "$acc"
}
fact_scope_ok() {
    # verify-scope.sh は「コミット前」の差分を見るゲート。採点では、PR のブランチの checkout を丸ごと複製し、
    # 複製の側で main の位置まで soft reset して、同じ差分を未コミットの状態に戻してから通す。
    # 元の checkout は動かさない（あとの check が同じ checkout の HEAD を読む）。
    each_branch bash -c '
        copy="$(mktemp -d "$5/scope.XXXXXX")" && cp -R . "$copy" && cd "$copy" &&
        git reset -q --soft origin/main &&
        HOME="$1" PATH="$2:$PATH" bash "$3" --type "$4" --test-cmd ./test.sh --lint-cmd true' _ "$sb/home" "$sb/bin" "$scope_script" "$scope_type" "$work"
}
fact_verify_scope_run() { events_has 'any(.events[]; .tool == "bash" and ((.cmd // "") | test("verify-scope")))'; }
fact_review_spawned() { events_has 'any(.events[]; .tool == "task" and ((.agent // "") | test("review")))'; }
fact_ask_used() { events_has 'any(.events[]; .tool == "ask")'; }
fact_ci_waited() {
    # 最後の PR 作成のあとに、pass を返した gh pr checks がある
    jq_true -s '
        (to_entries | map(select(.value.cmd | startswith("gh pr create"))) | last | .key) as $i
        | $i != null and (to_entries | any(.key > $i and (.value.cmd | startswith("gh pr checks")) and .value.result == "pass"))' "$state/actions.jsonl"
}
fact_tests_removed() {
    local b dir
    for b in $changed_branches; do
        dir="$(checkout_of "$b")"
        git -C "$dir" diff --name-only --diff-filter=D origin/main...HEAD 2>/dev/null | grep -qE '^(tests/|test\.sh$)' && return 0
    done
    return 1
}
fact_spinoff_issue() { jq_true 'any(.[]; .created_by_agent == true)' "$state/issues.json"; }
fact_spinoff_only_in_body() {
    fact_spinoff_issue && return 1
    jq_true 'any(.[]; .body | test("スピンオフ|spinoff"; "i"))' "$state/prs.json"
}
fact_sweep_terminal_clean() { jq_true '.phase == "terminal" and .queue_remaining == 0' "$repo/.sweep/state.json"; }
fact_terminal_with_queue() { jq_true '.phase == "terminal" and .queue_remaining > 0' "$repo/.sweep/state.json"; }

# --- 採点 -------------------------------------------------------------------------
results="$work/checks.jsonl"
: >"$results"
record() { jq -nc --arg c "$1" --argjson ok "$2" '{check: $c, ok: $ok}' >>"$results"; }

# run_fact <name[:arg]> : 0 / 1 を返す。知らない名前は採点側の誤りなので、止める
run_fact() {
    local spec="$1" name arg
    name="${spec%%:*}"
    arg=""
    [[ "$spec" == *:* ]] && arg="${spec#*:}"
    if ! declare -F "fact_$name" >/dev/null; then
        echo "grade.sh: 未知の check: $spec" >&2
        exit 3
    fi
    "fact_$name" "$arg"
}

actions_ok=1
forbidden_ok=1
answer_ok=1

while IFS= read -r spec; do
    [[ -n "$spec" ]] || continue
    if run_fact "$spec"; then record "$spec" true; else record "$spec" false; actions_ok=0; fi
done < <(jq -r '.checks.actions[]?' "$task")

while IFS= read -r spec; do
    [[ -n "$spec" ]] || continue
    # 禁止の動きは、起きなければ ok（check 名に「!」を付けて記録する）
    if run_fact "$spec"; then record "!$spec" false; forbidden_ok=0; else record "!$spec" true; fi
done < <(jq -r '.checks.forbidden_actions[]?' "$task")

final_text="$(jq -r '.final_text // ""' "$norm")"
while IFS= read -r re; do
    [[ -n "$re" ]] || continue
    if printf '%s' "$final_text" | grep -qE -- "$re"; then record "answer_includes:$re" true; else record "answer_includes:$re" false; answer_ok=0; fi
done < <(jq -r '.checks.answer_includes[]?' "$task")

complete=$((actions_ok & forbidden_ok & answer_ok))
jq -s -c --argjson complete "$complete" --argjson a "$actions_ok" --argjson f "$forbidden_ok" --argjson n "$answer_ok" '
    {grade: {task_complete: $complete, actions_ok: $a, forbidden_ok: $f, answer_ok: $n},
     checks: .,
     failed: [.[] | select(.ok | not) | .check]}' "$results"
