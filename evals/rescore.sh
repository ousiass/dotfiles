#!/usr/bin/env bash
# 保存した生の出力（<variant>/runs/<タスク>-r<N>/out/raw/*.out.gz。run.sh --live が残す）から、採点し直す。モデルは呼ばない。
#
#   evals/rescore.sh <variant ディレクトリ>   （<variant>/results.jsonl と <variant>/runs/ がある場所）
#
# 出力（TSV）: task / rep / stored / last_only / current
#   stored     results.jsonl の grade.task_complete（その実行時の採点）
#   last_only  最後のメッセージだけで answer_includes を採点した場合（旧方式）。ほかは current と同じ
#   current    いまの grade.sh と同じ読み取りで採点した場合:
#                - answer_includes は、メインの回答すべて（answer_text）から探し、#<n> は GitHub の Issue 番号（evals/sandbox/issue-map.json）も許す
#                - verify_scope_run は、つなげたコマンド（; && | のあと）の verify-scope.sh --type も数える（lib/regex.sh）
#   answer_includes と verify_scope_run 以外のチェックは、保存した結果（failed）をそのまま使う（それらは生の出力だけでは採点し直せない）。
#   raw が無い行は「raw なし」と出す（再採点できない）。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/adapt.sh
. "$EVALS_DIR/lib/adapt.sh"
# shellcheck source=lib/regex.sh
. "$EVALS_DIR/lib/regex.sh"
dir="${1:?使い方: rescore.sh <variant ディレクトリ>}"
tasks="$EVALS_DIR/tasks.jsonl"
issue_map="$EVALS_DIR/sandbox/issue-map.json"

printf '%s\t%s\t%s\t%s\t%s\n' task rep stored last_only current
while IFS= read -r row; do
    id="$(jq -r .prompt_id <<<"$row")"
    rep="$(jq -r .rep <<<"$row")"
    stored="$(jq -r '.grade.task_complete' <<<"$row")"
    # phase-run.sh は 1 回ずつ run.sh --rep 1 で回して rep を振り直すので、ファイル名の rep は 1。ディレクトリ（<タスク>-r<N>）で探す
    raw="$(find "$dir/runs/$id-r$rep/out/raw" -name "$id-r*.out.gz" 2>/dev/null | head -1)"
    if [[ -z "$raw" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$stored" "raw なし" "raw なし"
        continue
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/rescore.XXXXXX")"
    gzip -dc "$raw" >"$tmp"
    norm="$(adapt_claude "$tmp")"
    rm -f "$tmp"
    final_text="$(jq -r '.final_text // ""' <<<"$norm")"
    answer_text="$(jq -r '.answer_text // .final_text // ""' <<<"$norm")"
    # answer_includes と verify_scope_run 以外で落ちたチェックがあるか（あれば、どの採点でも不合格）
    other_failed="$(jq -r '[.failed[]? | select((startswith("answer_includes:") or . == "verify_scope_run") | not)] | length' <<<"$row")"
    map="$(jq -c --arg id "$id" '[.[] | select(.task == $id)] | sort_by(.local) | map(.number)' "$issue_map")"
    [[ "$map" != "[]" ]] || map=""
    last=1 cur=1
    while IFS= read -r re; do
        [[ -n "$re" ]] || continue
        re_x="$(expand_issue_refs "$re" "$map")"
        printf '%s' "$final_text" | grep -qE -- "$re_x" || last=0
        printf '%s' "$answer_text" | grep -qE -- "$re_x" || cur=0
    done < <(jq -r --arg id "$id" 'select(.id == $id) | .checks.answer_includes[]?' "$tasks")
    # verify_scope_run: 保存した結果で落ちていなければ、そのまま通す。落ちていれば、いまの判定で見直す
    verify=1
    if [[ "$(jq -r '(.failed | index("verify_scope_run")) != null' <<<"$row")" == true ]]; then
        jq -r --arg re "$VERIFY_SCOPE_GATE_RE" 'any(.events[]; .tool == "bash" and ((.cmd // "") | test($re)))' <<<"$norm" | grep -qx true || verify=0
    fi
    pre=0
    [[ "$other_failed" -eq 0 ]] && pre=1
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$stored" "$((pre * last * verify))" "$((pre * cur * verify))"
done < <(jq -c 'select(.status == "ok")' "$dir/results.jsonl")
