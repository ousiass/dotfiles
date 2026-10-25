#!/usr/bin/env bash
# evals/（エージェント構成変更のための e2e eval 基盤）の配線の回帰テスト。モデルは呼ばない。
# フレームワークは使わず bash だけで完結させる。
#
#   ./tests/evals_dry_test.sh
#
# 確かめること:
#   1. claude / omp の両方で、dry モードのタスクセット全件がハーネスエラー 0 で完走し、正しい動きは満点になる
#   2. WATCHDOG の逸脱（--violate）を、採点が検出する（逸脱ごとに、期待する check が落ちる）
#   3. WATCHDOG の 6 件と Break map の各項目に、検出タスクか「該当なし」の理由がある
# 実際の claude / omp の出力形式との一致は、このテストでは確かめられない（evals/README.md の「未検証」）。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
EVALS="$DOTFILES_DIR/evals"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

check_eq() {
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then ok "$name"; else ng "$name (期待 $want / 実際 $got)"; fi
}

if ! command -v jq >/dev/null; then
    ng "jq が必要です"
    exit 1
fi

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
# 実行が一時ディレクトリを残さないことも見る（run.sh は $TMPDIR の下にだけ作る）
export TMPDIR="$tmp/scratch"
mkdir -p "$TMPDIR"

n_tasks="$(jq -s length "$EVALS/tasks.jsonl")"
n_violations="$(jq -s '[.[].violations[]?] | length' "$EVALS/tasks.jsonl")"

for harness in claude omp; do
    # --- 1. 正しい動き -----------------------------------------------------------
    out="$tmp/pass-$harness"
    log="$("$EVALS/run.sh" --harness "$harness" --dry --rep 1 --out "$out" 2>&1)"
    rc=$?
    check_eq "$harness 正しい動き: 完走する (exit 0)" 0 "$rc"
    [[ "$rc" -eq 0 ]] || printf '%s\n' "$log"
    check_eq "$harness 正しい動き: ハーネスエラー 0" 0 "$(jq -r .harness_errors "$out/run.json" 2>/dev/null)"
    check_eq "$harness 正しい動き: 全タスクが 1 行ずつ" "$n_tasks" "$(jq -s length "$out/results.jsonl")"
    check_eq "$harness 正しい動き: 全行 status=ok" "$n_tasks" "$(jq -s '[.[] | select(.status == "ok")] | length' "$out/results.jsonl")"
    bad="$(jq -r 'select(.grade.task_complete != 1) | "\(.prompt_id): \(.failed | join(", "))"' "$out/results.jsonl")"
    check_eq "$harness 正しい動き: 全タスクが満点" "" "$bad"
    check_eq "$harness 正しい動き: モデル呼び出しと使用量が取れている" 0 "$(jq -s '[.[] | select((.model_calls // 0) < 1 or (.in_tokens // 0) < 1 or (.out_tokens // 0) < 1)] | length' "$out/results.jsonl")"
    check_eq "$harness 正しい動き: by_agent に main がある" 0 "$(jq -s '[.[] | select(.by_agent.main == null)] | length' "$out/results.jsonl")"
    check_eq "$harness 正しい動き: サブエージェントを by_agent に分けて数える（impl は plan / develop / review）" 3 "$(jq -s '[.[] | select(.prompt_id == "impl-bugfix")][0].by_agent | keys | map(select(. == "plan" or . == "develop" or . == "review")) | length' "$out/results.jsonl")"

    # --- 2. 逸脱を検出する -------------------------------------------------------
    vout="$tmp/violate-$harness"
    log="$("$EVALS/run.sh" --harness "$harness" --dry --violate --out "$vout" 2>&1)"
    rc=$?
    check_eq "$harness 逸脱: 完走する (exit 0)" 0 "$rc"
    [[ "$rc" -eq 0 ]] || printf '%s\n' "$log"
    check_eq "$harness 逸脱: 逸脱の数だけ実行する" "$n_violations" "$(jq -s length "$vout/results.jsonl")"
    # 逸脱ごとに、スクリプトの `# detects:` に書いた check（| 区切り）のどれかが落ちること
    missed=""
    while IFS= read -r row; do
        pid="$(jq -r .prompt_id <<<"$row")"
        v="${pid#*@}"
        want="$(sed -n 's/^# detects: //p' "$EVALS/scenarios/violations/$v.sh")"
        got="$(jq -r '.failed | map(ltrimstr("!")) | join("|")' <<<"$row")"
        complete="$(jq -r .grade.task_complete <<<"$row")"
        hit=0
        old_ifs="$IFS"
        IFS='|'
        for w in $want; do
            case "|$got|" in *"|$w|"*) hit=1 ;; esac
        done
        IFS="$old_ifs"
        if [[ "$hit" -ne 1 || "$complete" -ne 0 ]]; then missed="$missed $pid(期待 $want / 実際 $got)"; fi
    done < <(jq -c '.' "$vout/results.jsonl")
    check_eq "$harness 逸脱: すべて検出して不合格にする" "" "$missed"
done

# --- 3. 被覆 --------------------------------------------------------------------
# WATCHDOG.md の番号つき節（## 1. 〜）の数。節が増減したら、検出タスクの割り当てを見直す
n_watchdog="$(grep -cE '^## [0-9]+\.' "$DOTFILES_DIR/omp/WATCHDOG.md")"
check_eq "WATCHDOG: 節は 6 件（増減したら evals/tasks.jsonl の watchdog を見直す）" 6 "$n_watchdog"
for n in 1 2 3 4 5 6; do
    has_task="$(jq -s --argjson n "$n" '[.[] | select((.watchdog // []) | index($n))] | length' "$EVALS/tasks.jsonl")"
    # そのタスクに、逸脱の再現（violations）が 1 つ以上ある
    has_violation="$(jq -s --argjson n "$n" '[.[] | select((.watchdog // []) | index($n)) | select((.violations // []) | length > 0)] | length' "$EVALS/tasks.jsonl")"
    if [[ "$has_task" -ge 1 && "$has_violation" -ge 1 ]]; then ok "WATCHDOG $n: 検出タスクと逸脱の再現がある"; else ng "WATCHDOG $n: 検出タスクか逸脱の再現が無い"; fi
done

# Break map: 各項目に、実在するタスクがあるか、該当なしの理由がある
missing="$(jq -s -r --slurpfile bm "$EVALS/breakmap.json" '
    ([.[].id]) as $ids
    | $bm[0][]
    | select((.tasks | length) == 0 and ((.na_reason // "") == ""))
    | .id + ": タスクも該当なしの理由も無い"' "$EVALS/tasks.jsonl")"
check_eq "Break map: 各項目にタスクか該当なしの理由がある" "" "$missing"
unknown="$(jq -s -r --slurpfile bm "$EVALS/breakmap.json" '
    ([.[].id]) as $ids
    | $bm[0][] | .id as $b | .tasks[] | select(. as $t | $ids | index($t) | not) | "\($b): 存在しないタスク \(.)"' "$EVALS/tasks.jsonl")"
check_eq "Break map: 参照するタスクがすべて実在する" "" "$unknown"
# タスク側の breaks タグと Break map の tasks が食い違わない（片方だけに書いて忘れない）
mismatch="$(jq -s -r --slurpfile bm "$EVALS/breakmap.json" '
    . as $tasks
    | $bm[0][] | .id as $b
    | ([$tasks[] | select((.breaks // []) | index($b)) | .id] | sort) as $tagged
    | (.tasks | sort) as $listed
    | select($tagged != $listed)
    | "\($b): タスク側 \($tagged | join(",")) / breakmap 側 \($listed | join(","))"' "$EVALS/tasks.jsonl")"
check_eq "Break map: タスクの breaks と breakmap.json が一致する" "" "$mismatch"

# --- 本番に出ていない ------------------------------------------------------------
check_eq "dry の実行が一時ディレクトリを残さない" 0 "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"

exit "$fail"
