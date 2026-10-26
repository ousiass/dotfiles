#!/usr/bin/env bash
# 保存した生の出力（<variant>/runs/<タスク>-r<N>/out/raw/*.out.gz。run.sh --live が残す）から、answer_includes だけを採点し直す。モデルは呼ばない。
#
#   evals/rescore.sh <variant ディレクトリ>   （<variant>/results.jsonl と <variant>/runs/ がある場所）
#
# 出力（TSV）: タスク / rep / 保存した結果 / 最後のメッセージだけで採点 / メインの回答すべてで採点（現行）
#   保存した結果 = results.jsonl の grade.task_complete。actions_ok と forbidden_ok はそのまま使い、answer_includes だけを採点し直す。
#   raw が無い行は「raw なし」と出す（再採点できない。raw を残すようにしたのは、この採点の変更と同じ版から）。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/adapt.sh
. "$EVALS_DIR/lib/adapt.sh"
dir="${1:?使い方: rescore.sh <variant ディレクトリ>}"
tasks="$EVALS_DIR/tasks.jsonl"

printf '%s\t%s\t%s\t%s\t%s\n' task rep stored last_only all_main
while IFS= read -r row; do
    id="$(jq -r .prompt_id <<<"$row")"
    rep="$(jq -r .rep <<<"$row")"
    stored="$(jq -r '.grade.task_complete' <<<"$row")"
    raw="$(find "$dir/runs/$id-r$rep/out/raw" -name "$id-r$rep.out.gz" 2>/dev/null | head -1)"
    if [[ -z "$raw" ]]; then
        printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$stored" "raw なし" "raw なし"
        continue
    fi
    tmp="$(mktemp "${TMPDIR:-/tmp}/rescore.XXXXXX")"
    gzip -dc "$raw" >"$tmp"
    norm="$(adapt_claude "$tmp")"
    rm -f "$tmp"
    pre="$(jq -r '(.grade.actions_ok * .grade.forbidden_ok)' <<<"$row")"
    last=1 all=1
    while IFS= read -r re; do
        [[ -n "$re" ]] || continue
        jq -r '.final_text // ""' <<<"$norm" | grep -qE -- "$re" || last=0
        jq -r '.answer_text // .final_text // ""' <<<"$norm" | grep -qE -- "$re" || all=0
    done < <(jq -r --arg id "$id" 'select(.id == $id) | .checks.answer_includes[]?' "$tasks")
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$stored" "$((pre * last))" "$((pre * all))"
done < <(jq -c 'select(.status == "ok")' "$dir/results.jsonl")
