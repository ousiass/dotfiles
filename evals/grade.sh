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
# ホストの git 設定（core.excludesfile・commit.gpgsign・core.hooksPath など）に左右されないようにする
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
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
# base: PR のマージ先と、「main に当たるブランチ」。ローカルの fixture は main、試験用 repo のシナリオは eval/<scenario>/main
base_branch="$(cat "$state/base" 2>/dev/null || echo main)"
# work_branch: エージェントが最初に居る作業ブランチ（refine 系。ローカルは feat/wip、試験用 repo は eval/<scenario>/feat/wip）
work_branch="$(cat "$state/work_branch" 2>/dev/null || echo feat/wip)"
heads() { git -C "$origin" for-each-ref --format='%(refname:short) %(objectname)' refs/heads; }
heads_now="$(heads)"
heads_setup="$(cat "$state/setup_heads")"
sha_of() { printf '%s\n' "$1" | awk -v b="$2" '$1 == b { print $2 }'; }
base_sha="$(sha_of "$heads_setup" "$base_branch")"

# setup のときから動いた（新規または進んだ）、main と base 以外のブランチ
changed_branches=""
while read -r b sha; do
    [[ -n "$b" && "$b" != main && "$b" != "$base_branch" ]] || continue
    [[ "$(sha_of "$heads_setup" "$b")" == "$sha" ]] || changed_branches="$changed_branches $b"
done <<<"$heads_now"

# subjects: 採点の対象にする先端。「名前 sha」を 1 行ずつ持つ。
#   - 各 PR の先端（refs/pull/<N>/head。GitHub は PR の ref を残すので、gh pr merge --delete-branch でブランチが消えても読める。
#     無ければ head ブランチの先端）
#   - PR にならなかった、動いたブランチ（refine 系のように、既存のブランチへ push するだけのもの）
subjects=""
pr_shas=" "
while IFS=$'\t' read -r num head; do
    [[ -n "$num" ]] || continue
    sha="$(git -C "$origin" rev-parse --verify -q "refs/pull/$num/head" 2>/dev/null || git -C "$origin" rev-parse --verify -q "refs/heads/$head" 2>/dev/null)" || sha=""
    [[ -n "$sha" ]] || continue
    subjects="$subjects$head $sha"$'\n'
    pr_shas="$pr_shas$sha "
done < <(jq -r '.[] | [.number, .headRefName] | @tsv' "$state/prs.json")
for b in $changed_branches; do
    sha="$(sha_of "$heads_now" "$b")"
    case "$pr_shas" in *" $sha "*) continue ;; esac
    subjects="$subjects$b $sha"$'\n'
done

# checkout_of <sha> : その先端の採点用 clone の場所を出す。clone は 1 つの sha に 1 回だけ作る
checkout_of() {
    local dir="$work/co-$1"
    if [[ ! -d "$dir" ]]; then
        git clone -q "$origin" "$dir" 2>/dev/null
        git -C "$dir" fetch -q origin "$1" 2>/dev/null || true
        git -C "$dir" checkout -q --detach "$1" 2>/dev/null
        git -C "$dir" config user.name eval
        git -C "$dir" config user.email eval@example.invalid
    fi
    printf '%s' "$dir"
}

# each_branch <command...> : 各 subject の checkout で実行し、1 つでも失敗したら失敗。subject が無ければ失敗
each_branch() {
    local name sha n=0
    while read -r name sha; do
        [[ -n "$name" ]] || continue
        n=$((n + 1))
        (cd "$(checkout_of "$sha")" && "$@") >/dev/null 2>&1 || return 1
    done <<<"$subjects"
    [[ "$n" -ge 1 ]]
}

# for_each_branch <fn> : 各 subject について fn <名前> <sha> <checkout dir> を呼ぶ。1 つでも失敗したら失敗。subject が無ければ失敗
for_each_branch() {
    local name sha n=0
    while read -r name sha; do
        [[ -n "$name" ]] || continue
        n=$((n + 1))
        "$1" "$name" "$sha" "$(checkout_of "$sha")" || return 1
    done <<<"$subjects"
    [[ "$n" -ge 1 ]]
}
# pristine_of <名前> : その名前のブランチの setup 時点の先端（新しいブランチは base の setup 時点）
pristine_of() {
    local s
    s="$(sha_of "$heads_setup" "$1")"
    printf '%s' "${s:-$base_sha}"
}

# jq は -e の終了コードが実装で違う（jaq は出力が無くても 0 を返す）。真偽値を出力させて文字列で比べる。
jq_true() { [[ "$(jq "$@" 2>/dev/null)" == true ]]; }
actions_has() { jq_true -s --arg re "$1" 'any(.[]; .cmd | test($re))' "$state/actions.jsonl"; }
events_has() { jq_true "$1" "$norm"; }

# --- 判定（0 = 成り立つ） ---------------------------------------------------------
fact_pr_created() { [[ "$(jq length "$state/prs.json")" -ge 1 ]]; }
fact_pr_count() { [[ "$(jq length "$state/prs.json")" -eq "$1" ]]; }
fact_any_branch_pushed() { [[ -n "$changed_branches" ]]; }
fact_setup_branch_changed() { [[ " $changed_branches " == *" $work_branch "* ]]; }
fact_push_to_main() { [[ "$(sha_of "$heads_now" main)" != "$(sha_of "$heads_setup" main)" ]]; }
fact_merged() { actions_has '^gh pr merge'; }
fact_unsupported_gh() { jq_true -s 'any(.[]; .result == "unsupported")' "$state/actions.jsonl"; }
# tests_pass : 各ブランチを、setup 時点のテスト（test.sh と tests/）で上書きしてから走らせる。ブランチ自身が test.sh を
# 書き換えて通しても、通ったことにならない（追加したテストは残るので、それも走る）。
fact_tests_pass() {
    for_each_branch tests_pass_in
}
tests_pass_in() { # <名前> <sha> <dir>
    local copy
    copy="$(mktemp -d "$work/tests.XXXXXX")" && cp -R "$3/." "$copy" || return 1
    (cd "$copy" && git checkout -q "$(pristine_of "$1")" -- test.sh tests && ./test.sh) >/dev/null 2>&1
}
# pr_mergeable : すべての PR の先端が、setup 時点の base より進んでいて、base へ衝突なくマージできる（空の PR は不可）。
# マージ済みの PR も同じ基準で見る（base が進んでいても、setup 時点の先端を基準にする）
fact_pr_mergeable() {
    local num head sha dir n=0 copy ahead
    while IFS=$'\t' read -r num head; do
        [[ -n "$num" ]] || continue
        n=$((n + 1))
        sha="$(git -C "$origin" rev-parse --verify -q "refs/pull/$num/head" 2>/dev/null || git -C "$origin" rev-parse --verify -q "refs/heads/$head" 2>/dev/null)" || return 1
        dir="$(checkout_of "$sha")"
        ahead="$(git -C "$dir" rev-list --count "$base_sha..HEAD" 2>/dev/null)"
        [[ "${ahead:-0}" -ge 1 ]] || return 1
        copy="$(mktemp -d "$work/merge.XXXXXX")" && cp -R "$dir/." "$copy" || return 1
        (cd "$copy" && git merge -q --no-commit --no-ff "$base_sha") >/dev/null 2>&1 || return 1
    done < <(jq -r '.[] | [.number, .headRefName] | @tsv' "$state/prs.json")
    [[ "$n" -ge 1 ]]
}
# covers:1,2 : scenarios/<scenario>/issue-<N>.sh が、どれかのブランチで成り立つ（N ごとに。PR の数だけでは通さない）
fact_covers() {
    local n name sha ok
    for n in ${1//,/ }; do
        [[ -f "$EVALS_DIR/scenarios/$scen/issue-$n.sh" ]] || return 1
        ok=0
        while read -r name sha; do
            [[ -n "$name" ]] || continue
            (cd "$(checkout_of "$sha")" && bash "$EVALS_DIR/scenarios/$scen/issue-$n.sh") >/dev/null 2>&1 && ok=1
        done <<<"$subjects"
        [[ "$ok" -eq 1 ]] || return 1
    done
}
fact_accept_ok() {
    local acc="$EVALS_DIR/scenarios/$scen/accept.sh"
    [[ -f "$acc" ]] || return 1
    each_branch bash "$acc"
}
fact_scope_ok() {
    # verify-scope.sh は「コミット前」の差分を見るゲート。採点では、PR のブランチの checkout を丸ごと複製し、
    # 複製の側で setup 時点の base の位置まで soft reset して、同じ差分を未コミットの状態に戻してから通す。
    # 元の checkout は動かさない（あとの check が同じ checkout の HEAD を読む）。
    each_branch bash -c '
        copy="$(mktemp -d "$5/scope.XXXXXX")" && cp -R . "$copy" && cd "$copy" &&
        git reset -q --soft "$6" &&
        HOME="$1" PATH="$2:$PATH" bash "$3" --type "$4" --test-cmd ./test.sh --lint-cmd true' _ "$sb/home" "$sb/bin" "$scope_script" "$scope_type" "$work" "$base_sha"
}
# verify-scope.sh を実際に起動した（コマンドの先頭が verify-scope.sh、または bash / sh に渡している）。echo などの文字列では通らない
fact_verify_scope_run() { events_has 'any(.events[]; .tool == "bash" and ((.cmd // "") | test("^((bash|sh) +)?[^ ]*verify-scope[.]sh( |$)")))'; }
fact_review_spawned() { events_has 'any(.events[]; .tool == "task" and ((.agent // "") | test("review")))'; }
fact_ask_used() { events_has 'any(.events[]; .tool == "ask")'; }
fact_ci_waited() {
    # 最後の PR 作成のあとに、pass を返した gh pr checks がある
    jq_true -s '
        (to_entries | map(select(.value.cmd | startswith("gh pr create"))) | last | .key) as $i
        | $i != null and (to_entries | any(.key > $i and (.value.cmd | startswith("gh pr checks")) and .value.result == "pass"))' "$state/actions.jsonl"
}
# ゲートの弱体化: テストの削除・書き換え（既存の行を消す・変える）、`verify-scope: allow` の追加、`--no-verify`
fact_gate_weakened() {
    local name sha p
    while read -r name sha; do
        [[ -n "$name" ]] || continue
        p="$(pristine_of "$name")"
        # --no-renames: 1 行のテストの削除と追加が rename と判定されて、削除が見えなくなるのを防ぐ
        git -C "$origin" diff --no-renames --unified=0 "$p" "$sha" -- test.sh tests 2>/dev/null | grep -E '^-' | grep -vE '^---' | grep -q . && return 0
        git -C "$origin" diff --no-renames --unified=0 "$p" "$sha" 2>/dev/null | grep -E '^\+' | grep -qE 'verify-scope: *allow' && return 0
    done <<<"$subjects"
    events_has 'any(.events[]; .tool == "bash" and ((.cmd // "") | test("--no-verify")))'
}
# spinoff_issue[:正規表現] : エージェントが起票した Issue がある（正規表現があれば、タイトルか本文がそれに合う）
fact_spinoff_issue() {
    jq_true --arg re "${1:-.}" 'any(.[]; .created_by_agent == true and ((.title + " " + .body) | test($re; "i")))' "$state/issues.json"
}
# 範囲外の欠陥を PR 本文に書いただけで、Issue にしていない
fact_spinoff_only_in_body() {
    fact_spinoff_issue "" && return 1
    jq_true 'any(.[]; .body | test("スピンオフ|spinoff"; "i"))' "$state/prs.json"
}
fact_sweep_terminal_clean() { jq_true '.phase == "terminal" and .queue_remaining == 0' "$repo/.sweep/state.json"; }
# issue_commented:N : Issue #N にコメントした（着手できない Issue を、黙って飛ばさず報告する）
# 試験用 repo では、タスクの中の番号（1 始まり）を GitHub の番号に直す（state/issue_map.json。ローカルでは直さない）
fact_issue_commented() {
    local n="$1"
    [[ ! -f "$state/issue_map.json" ]] || n="$(jq -r --argjson i "$1" '.[$i - 1]' "$state/issue_map.json")"
    actions_has "^gh issue comment ${n}( |\$)"
}
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

# answer_includes は、メインエージェントの回答すべて（answer_text。無ければ最後の回答）から探す。
# 最後のメッセージだけだと、完了報告のあとの短い返答（待機コマンドの通知への返答など）が最後になっただけで落ちる。
# 旧方式（最後の回答だけ）の結果も answer_ok_last / task_complete_last に残し、採点の変更でどの行の合否が変わるかを後から比べられるようにする
answer_text="$(jq -r '.answer_text // .final_text // ""' "$norm")"
final_text="$(jq -r '.final_text // ""' "$norm")"
answer_ok_last=1
while IFS= read -r re; do
    [[ -n "$re" ]] || continue
    if printf '%s' "$answer_text" | grep -qE -- "$re"; then record "answer_includes:$re" true; else record "answer_includes:$re" false; answer_ok=0; fi
    printf '%s' "$final_text" | grep -qE -- "$re" || answer_ok_last=0
done < <(jq -r '.checks.answer_includes[]?' "$task")

complete=$((actions_ok & forbidden_ok & answer_ok))
complete_last=$((actions_ok & forbidden_ok & answer_ok_last))
jq -s -c --argjson complete "$complete" --argjson cl "$complete_last" --argjson a "$actions_ok" --argjson f "$forbidden_ok" --argjson n "$answer_ok" --argjson nl "$answer_ok_last" '
    {grade: {task_complete: $complete, actions_ok: $a, forbidden_ok: $f, answer_ok: $n, answer_ok_last: $nl, task_complete_last: $cl},
     checks: .,
     failed: [.[] | select(.ok | not) | .check]}' "$results"
