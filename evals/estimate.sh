#!/usr/bin/env bash
# 有料の実行の前に出す、規模（タスク数 × rep × ハーネス）とトークン見積もり。モデルは呼ばない。
#
#   evals/estimate.sh [--reps N] [--harnesses N] [--runs N]
#
#   --reps        1 タスクあたりの回数（既定 2）
#   --harnesses   ハーネスの数（claude と omp の両方で 2。既定 2）
#   --runs        同じタスクセットを何回流すか（Phase 1 の基準値 1 + Phase 2 + Phase 3 で既定 3）
#
# 重さ（tasks.jsonl の weight）ごとの 1 回あたりの使用量は evals/calibration.json から読む。
# calibration.json は、過去に omp で実際に動いた session の実測の分位点で、evals/observe-usage.sh で作り直せる。
# タスクの重さと対応する分位点は、calibration.json の `weights` に書いてある。トークンだけを数え、価格は推測しない。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reps=2
harnesses=2
runs=3
while [[ $# -gt 0 ]]; do
    case "$1" in
    --reps)
        reps="${2:-}"
        shift 2
        ;;
    --harnesses)
        harnesses="${2:-}"
        shift 2
        ;;
    --runs)
        runs="${2:-}"
        shift 2
        ;;
    *)
        echo "estimate.sh: 不明な引数: $1" >&2
        exit 2
        ;;
    esac
done

jq -rn --slurpfile cal "$EVALS_DIR/calibration.json" --slurpfile tasks <(jq -s . "$EVALS_DIR/tasks.jsonl") \
    --argjson reps "$reps" --argjson harnesses "$harnesses" --argjson runs "$runs" '
  def m(x): (x / 1000000 * 10 | round) / 10;
  $cal[0] as $c
  | $tasks[0] as $t
  | ($t | group_by(.weight) | map({key: .[0].weight, value: length}) | from_entries) as $by
  | ($c.weights | to_entries | map(
        .key as $w | .value as $src
        | ($by[$w] // 0) as $n
        | {weight: $w, tasks: $n, source: $src,
           calls: ($c.classes[$src].calls * $n), out: ($c.classes[$src].out * $n),
           fresh: ($c.classes[$src].fresh * $n), cache_read: ($c.classes[$src].cache_read * $n)})) as $rows
  | ($rows | {calls: (map(.calls) | add), out: (map(.out) | add), fresh: (map(.fresh) | add), cache_read: (map(.cache_read) | add)}) as $one
  | ($t | length) as $nt
  | ($nt * $reps * $harnesses) as $per_set
  | ($per_set * $runs) as $total
  | "タスク数: \($nt)（" + ($by | to_entries | map("\(.key) \(.value)") | join(" / ")) + "）",
    "1 セット = タスク \($nt) × rep \($reps) × ハーネス \($harnesses) = \($per_set) 回の実行",
    "Phase 1〜3 = \($runs) セット（基準値・Plan 取り込み・main 修正）= \($total) 回の実行（flaky の再実行は含まない）",
    "",
    "1 回の実行あたりの使用量（タスクの重さごとの中央値。calibration.json）:",
    "  | 重さ | タスク数 | 由来 | モデル呼び出し | 出力 | 新規入力（input + cache 書き） | cache 読み |",
    "  |---|---|---|---|---|---|---|",
    ($rows[] | "  | \(.weight) | \(.tasks) | \(.source) | \(.calls / .tasks | round) | \(.out / .tasks | round) | \(.fresh / .tasks | round) | \(.cache_read / .tasks | round) |"),
    "",
    "合計（トークン、100 万単位）:",
    "  | 範囲 | モデル呼び出し | 出力 | 新規入力 | cache 読み |",
    "  |---|---|---|---|---|",
    "  | 1 タスクセット × rep × ハーネス（= 1 回の基準値） | \($one.calls * $reps * $harnesses) | \(m($one.out * $reps * $harnesses))M | \(m($one.fresh * $reps * $harnesses))M | \(m($one.cache_read * $reps * $harnesses))M |",
    "  | Phase 1〜3（\($runs) セット） | \($one.calls * $reps * $harnesses * $runs) | \(m($one.out * $reps * $harnesses * $runs))M | \(m($one.fresh * $reps * $harnesses * $runs))M | \(m($one.cache_read * $reps * $harnesses * $runs))M |",
    "",
    "出所: \($c.provenance)",
    "注意: 出所の実測は実 repo（大きな題材）の中央値なので、eval の題材（小さな bash ライブラリ）に対しては上限の目安。実測は Phase 1 の最初に 1 タスク × 1 rep を実際に走らせて確かめる。cache 読みは課金単価が低いので、新規入力と出力を別に見る。"'
