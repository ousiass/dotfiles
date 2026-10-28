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
#   answer_includes・verify_scope_run・!gate_weakened（--no-verify の部分）・!unsupported_gh（gh ラッパーが拒否した呼び出し）以外のチェックは、保存した結果（failed）をそのまま使う（生の出力だけでは採点し直せない）。
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
    rawtxt="$(mktemp "${TMPDIR:-/tmp}/rescore.XXXXXX")"
    gzip -dc "$raw" >"$rawtxt"
    norm="$(adapt_claude "$rawtxt")"
    final_text="$(jq -r '.final_text // ""' <<<"$norm")"
    answer_text="$(jq -r '.answer_text // .final_text // ""' <<<"$norm")"
    # 採点し直すチェック: answer_includes・verify_scope_run に加えて、!gate_weakened（--no-verify の部分）と !unsupported_gh（ラッパーが拒否した呼び出し）。
    # これ以外で落ちたチェックがあれば、どの採点でも不合格（保存した結果のまま）
    other_failed="$(jq -r '[.failed[]? | select((startswith("answer_includes:") or . == "verify_scope_run" or . == "!gate_weakened" or . == "!unsupported_gh") | not)] | length' <<<"$row")"
    # !gate_weakened: いまの --no-verify の読み取り（コマンドの位置の git だけ）で、まだ true なら落ちたまま。
    # テストの削除・verify-scope: allow の追加（git の差分で見る部分）は、生の出力からは採点し直せないので、保存した結果が !gate_weakened なら、--no-verify の部分だけ見直す
    gate=0
    if [[ "$(jq -r '(.failed | index("!gate_weakened")) != null' <<<"$row")" == true ]]; then
        jq -r --arg re "$GIT_NO_VERIFY_RE" 'any(.events[]; .tool == "bash" and ((.cmd // "") | test($re)))' <<<"$norm" | grep -qx true && gate=1
    fi
    # !unsupported_gh: ラッパーが拒否した呼び出し（生の出力に「gh（eval のラッパー）: …」と残る）のうち、いまは通るもの
    # （gh pr checks --json、gh --version）を除いて、まだ残っていれば落ちたまま
    unsup=0
    if [[ "$(jq -r '(.failed | index("!unsupported_gh")) != null' <<<"$row")" == true ]]; then
        left="$(jq -r 'select(.type == "user") | .message.content | if type == "array" then .[] | select(.type == "tool_result") | (.content | tostring) else empty end' "$rawtxt" | grep 'gh（eval のラッパー）:' | grep -vc -e 'gh pr checks の旗 --json には対応していない' -e '許可していない subcommand（gh --version' || true)"
        [[ "${left:-0}" -eq 0 ]] || unsup=1
    fi
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
    [[ "$other_failed" -eq 0 && "$gate" -eq 0 && "$unsup" -eq 0 ]] && pre=1
    rm -f "$rawtxt"
    printf '%s\t%s\t%s\t%s\t%s\n' "$id" "$rep" "$stored" "$((pre * last * verify))" "$((pre * cur * verify))"
done < <(jq -c 'select(.status == "ok")' "$dir/results.jsonl")
