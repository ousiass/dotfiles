#!/usr/bin/env bash
# 有料の実行の前に出す、規模（タスク数 × rep × ハーネス）とトークン見積もり。モデルは呼ばない。
#
#   evals/estimate.sh [--reps N] [--harnesses N]
#
#   --reps        1 タスクあたりの回数（既定 2）
#   --harnesses   ハーネスの数（claude と omp の両方で 2。既定 2）
#
# Phase ごとの対象は Issue #56 の定義に合わせる:
#   Phase 1  現行構成の基準値        全タスク
#   Phase 2  impl の Plan を取り込む  impl 系タスク（skill が impl）だけ。issue-sweep の並列 develop / review は対象外
#   Phase 3  impl で main が修正する  impl 系タスクだけ（impl のみ）
# 使用量は evals/calibration.json（過去の omp 実測の分位点。evals/observe-usage.sh で作り直せる）から読み、
# 1 点の値ではなく範囲で出す:
#   下限  どのタスクも「軽い impl（実測の p25）」並み。題材が数十行の bash ライブラリなので、ここまで小さくなりうる
#   中央  タスクの weight（light / normal / heavy）ごとの実測の分位点
#   上限  実 repo 並み。impl・refine は impl の p75、issue-sweep は sweep（Issue 2〜3 件）の p75
# 実測は実 repo（大きな題材）なので、上限は費用の確定値ではない。トークンだけを数え、価格は推測しない。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
reps=2
harnesses=2
while [[ $# -gt 0 ]]; do
    case "$1" in
    --reps | --harnesses)
        [[ $# -ge 2 && "$2" =~ ^[1-9][0-9]*$ ]] || {
            echo "estimate.sh: $1 には 1 以上の整数が必要です" >&2
            exit 2
        }
        ;;
    esac
    case "$1" in
    --reps)
        reps="$2"
        shift 2
        ;;
    --harnesses)
        harnesses="$2"
        shift 2
        ;;
    *)
        echo "estimate.sh: 不明な引数: $1" >&2
        exit 2
        ;;
    esac
done

jq -rn --slurpfile cal "$EVALS_DIR/calibration.json" --slurpfile tasks <(jq -s . "$EVALS_DIR/tasks.jsonl") \
    --argjson reps "$reps" --argjson harnesses "$harnesses" '
  def m(x): (x / 1000000 * 10 | round) / 10;
  $cal[0] as $c
  | $tasks[0] as $t
  | def cls($src): $c.classes[$src] // error("calibration.json に \($src) が無い");
  def src($task; $mode):
    if $mode == "low" then "impl_p25"
    elif $mode == "high" then (if $task.skill == "issue-sweep" then "sweep_2to3_p75" else "impl_p75" end)
    else ($c.weights[$task.weight] // error("tasks.jsonl の weight が calibration.json の weights に無い: \($task.weight)")) end;
  def sum($ts; $mode; $k): [$ts[] | cls(src(.; $mode))[$k]] | add // 0;
  ($t | map(select(.skill == "impl"))) as $impl
  | ($t | length) as $nt
  | ($impl | length) as $ni
  | [{p: "Phase 1（基準値、全タスク）", ts: $t},
     {p: "Phase 2（impl の Plan を取り込む、impl 系のみ）", ts: $impl},
     {p: "Phase 3（impl で main が修正、impl のみ）", ts: $impl}] as $phases
  | "タスク数: \($nt)（うち impl 系 \($ni)。Phase 2 / 3 は impl 系だけ）",
    "1 セット = タスク × rep \($reps) × ハーネス \($harnesses)",
    "  Phase 1: \($nt) × \($reps) × \($harnesses) = \($nt * $reps * $harnesses) 回、Phase 2: \($ni) × \($reps) × \($harnesses) = \($ni * $reps * $harnesses) 回、Phase 3: 同じく \($ni * $reps * $harnesses) 回",
    "  合計 \(($nt + 2 * $ni) * $reps * $harnesses) 回の実行（flaky の再実行は含まない）",
    "",
    "トークン（100 万単位。出力 / 新規入力 = input + cache 書き / cache 読み）:",
    "  | 範囲 | Phase | 実行回数 | モデル呼び出し | 出力 | 新規入力 | cache 読み |",
    "  |---|---|---|---|---|---|---|",
    ( ["low", "mid", "high"][] as $mode
      | ({low: "下限", mid: "中央", high: "上限"}[$mode]) as $lbl
      | $phases[] | .p as $p | .ts as $ts | (($ts | length) * $reps * $harnesses) as $runs
      | "  | \($lbl) | \($p) | \($runs) | \(sum($ts; $mode; "calls") * $reps * $harnesses) | \(m(sum($ts; $mode; "out") * $reps * $harnesses))M | \(m(sum($ts; $mode; "fresh") * $reps * $harnesses))M | \(m(sum($ts; $mode; "cache_read") * $reps * $harnesses))M |" ),
    ( ["low", "mid", "high"][] as $mode
      | ({low: "下限", mid: "中央", high: "上限"}[$mode]) as $lbl
      | "  | \($lbl) | **Phase 1〜3 の合計** | \(($nt + 2 * $ni) * $reps * $harnesses) | \(([$phases[] | sum(.ts; $mode; "calls")] | add) * $reps * $harnesses) | \(m(([$phases[] | sum(.ts; $mode; "out")] | add) * $reps * $harnesses))M | \(m(([$phases[] | sum(.ts; $mode; "fresh")] | add) * $reps * $harnesses))M | \(m(([$phases[] | sum(.ts; $mode; "cache_read")] | add) * $reps * $harnesses))M |" ),
    "",
    "出所: \($c.provenance)",
    "注意: 上限は実 repo の実測の p75 で、費用の確定値ではない。eval の題材は小さいので、実際は下限に近いはず。実測は Phase 1 の最初に 1 タスク × 1 rep を実際に走らせて確かめる。cache 読みは課金単価が低いので、新規入力と出力を別に見る。"'
