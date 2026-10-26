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
# ホストの設定（~/.gitconfig など）に依存していないことを見るため、HOME も使い捨てにする
export HOME="$tmp/home"
mkdir -p "$HOME"

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
    # answer_includes が落ちたとき、採点が厳しいのか言い落としかを読めるように、最終回答（先頭 800 文字）を残す。採点した回答と同じものであること
    check_eq "$harness 正しい動き: results.jsonl に最終回答（800 文字以内）が残る" 0 "$(jq -s '[.[] | select((.answer // "") == "" or (.answer | length) > 800)] | length' "$out/results.jsonl")"
    check_eq "$harness 正しい動き: impl-spinoff の answer は answer_includes（スピンオフ|spinoff）を満たす" 1 "$(jq -s '[.[] | select(.prompt_id == "impl-spinoff" and (.answer | test("スピンオフ|spinoff")))] | length' "$out/results.jsonl")"

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
    # `# watchdog: N` を持つ逸脱のスクリプトのうち、N を担当するタスクの violations に入っているものがある
    # （タスクに別の逸脱があるだけで通ってしまわないよう、逸脱のスクリプト単位で突き合わせる）
    found=""
    for f in "$EVALS"/scenarios/violations/*.sh; do
        grep -q "^# watchdog: $n\$" "$f" || continue
        v="$(basename "$f" .sh)"
        c="$(jq -s --argjson n "$n" --arg v "$v" '[.[] | select((.watchdog // []) | index($n)) | select((.violations // []) | index($v))] | length' "$EVALS/tasks.jsonl")"
        [[ "$c" -ge 1 ]] && found="$found $v"
    done
    if [[ -n "$found" ]]; then ok "WATCHDOG ${n}: 検出タスクと逸脱の再現がある（${found}）"; else ng "WATCHDOG ${n}: 逸脱のスクリプト（# watchdog: ${n}）が、担当のタスクの violations に無い"; fi
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

# --- --live の課金ガード（ガードが壊れても気づけるように、モデルを呼ぶ手前で止まることを見る） ----------
# PATH の先頭に「呼ばれたら記録して失敗する」claude / omp を置き、ガードを抜けて本物を呼ぶ事故を検出する
mkdir -p "$tmp/trap-bin"
for c in claude omp; do
    printf '#!/bin/sh\necho called >>"%s/model-called"\nexit 1\n' "$tmp" >"$tmp/trap-bin/$c"
    chmod +x "$tmp/trap-bin/$c"
done
# 隔離フォルダの中（evals/sandbox の env.sh と同じ変数）に見せる。ほかのガードを個別に確かめるため
run_live() {
    HOME="$tmp/home" EVAL_SANDBOX_ROOT="$tmp" CLAUDE_CONFIG_DIR="$tmp/home/.claude" PI_CODING_AGENT_DIR="$tmp/home/.omp/agent" \
        PATH="$tmp/trap-bin:$PATH" "$EVALS/run.sh" "$@" >/dev/null 2>&1
}
# 隔離フォルダの外（本物の HOME・設定）では、課金の確認と --model が揃っていても --live を拒否する
EVAL_CONFIRM_PAID=1 PATH="$tmp/trap-bin:$PATH" "$EVALS/run.sh" --harness omp --live --model m --out "$tmp/live0" >/dev/null 2>&1
check_eq "--live: 隔離フォルダの外は exit 2" 2 "$?"
check_eq "--live: 隔離フォルダの外では何も作らない" 0 "$(ls "$tmp/live0" 2>/dev/null | wc -l | tr -d ' ')"
run_live --harness claude --live --model m --out "$tmp/live1"
check_eq "--live: EVAL_CONFIRM_PAID 無しは exit 2" 2 "$?"
EVAL_CONFIRM_PAID=1 run_live --harness claude --live --out "$tmp/live2"
check_eq "--live: --model 無しは exit 2" 2 "$?"
EVAL_CONFIRM_PAID=1 run_live --harness omp --live --violate --model m --out "$tmp/live3"
check_eq "--live: --violate との併用は exit 2" 2 "$?"
run_live --harness claude
check_eq "--dry も --live も無いときは exit 2" 2 "$?"
run_live --harness
check_eq "値の無い旗で止まる（無限ループしない）" 2 "$?"
check_eq "ガードの手前で止まり、モデルを呼んでいない" 0 "$(ls "$tmp/model-called" 2>/dev/null | wc -l | tr -d ' ')"
# dry は PATH に本物（ここでは罠）の claude / omp があっても、それを呼ばない
PATH="$tmp/trap-bin:$PATH" "$EVALS/run.sh" --harness omp --dry --rep 1 --task refine-clean --out "$tmp/dry-trap" >/dev/null 2>&1
check_eq "dry: PATH に claude / omp があっても呼ばない" 0 "$(ls "$tmp/model-called" 2>/dev/null | wc -l | tr -d ' ')"
check_eq "dry: 罠がある PATH でも完走する" 1 "$(jq -s '[.[] | select(.status == "ok")] | length' "$tmp/dry-trap/results.jsonl" 2>/dev/null)"

# --- answer_includes は、メインの回答すべてから探す（最後のメッセージだけだと、待機コマンドの通知への返答が最後になっただけで落ちる） ---
# 実際に起きた形: 完了報告のあとに、通知への短い返答が最後のメッセージになる。サブエージェントのテキストは数えない
rs="$tmp/rescore/v"
mkdir -p "$rs/runs/impl-spinoff-r1/out/raw" "$rs/runs/impl-spinoff-r2/out/raw"
stream() { # stream <完了報告のテキスト> <サブエージェントのテキスト> : 完了報告 → サブエージェント → 通知への返答（最後）
    printf '%s\n' \
        '{"type":"system","subtype":"init","model":"m"}' \
        "{\"type\":\"assistant\",\"parent_tool_use_id\":null,\"message\":{\"id\":\"a1\",\"usage\":{\"input_tokens\":1,\"output_tokens\":5},\"content\":[{\"type\":\"text\",\"text\":\"$1\"}]}}" \
        "{\"type\":\"assistant\",\"parent_tool_use_id\":\"toolu_x\",\"message\":{\"id\":\"s1\",\"usage\":{\"input_tokens\":1,\"output_tokens\":5},\"content\":[{\"type\":\"text\",\"text\":\"$2\"}]}}" \
        '{"type":"assistant","parent_tool_use_id":null,"message":{"id":"a2","usage":{"input_tokens":1,"output_tokens":5},"content":[{"type":"text","text":"この通知は、待機コマンドが時間切れで停止しただけです。"}]}}' \
        '{"type":"result","result":"この通知は、待機コマンドが時間切れで停止しただけです。"}'
}
stream "完了報告: spinoff の Issue を起票しました" "余談" | gzip -c >"$rs/runs/impl-spinoff-r1/out/raw/impl-spinoff-r1.out.gz"
stream "完了報告: PR を作りました" "サブエージェントの spinoff の余談" | gzip -c >"$rs/runs/impl-spinoff-r2/out/raw/impl-spinoff-r2.out.gz"
printf '%s\n' \
    '{"prompt_id":"impl-spinoff","rep":1,"status":"ok","grade":{"task_complete":0,"actions_ok":1,"forbidden_ok":1}}' \
    '{"prompt_id":"impl-spinoff","rep":2,"status":"ok","grade":{"task_complete":0,"actions_ok":1,"forbidden_ok":1}}' \
    '{"prompt_id":"impl-bugfix","rep":1,"status":"ok","grade":{"task_complete":1,"actions_ok":1,"forbidden_ok":1}}' >"$rs/results.jsonl"
res="$("$EVALS/rescore.sh" "$rs" 2>&1)"
check_eq "rescore: 完了報告が最後のメッセージでなくても、メインの回答すべてから探して合格にする（保存 0 → 最後だけ 0 → 全部 1）" "impl-spinoff	1	0	0	1" "$(printf '%s\n' "$res" | grep '^impl-spinoff	1')"
check_eq "rescore: サブエージェントのテキストにだけ語があっても合格にしない" "impl-spinoff	2	0	0	0" "$(printf '%s\n' "$res" | grep '^impl-spinoff	2')"
check_eq "rescore: raw が無い行は再採点できないと出す" "impl-bugfix	1	1	raw なし	raw なし" "$(printf '%s\n' "$res" | grep '^impl-bugfix')"

# --- estimate.sh -------------------------------------------------------------------
est="$("$EVALS/estimate.sh" 2>&1)"
check_eq "estimate.sh: 成功する" 0 "$?"
case "$est" in *"タスク数: $n_tasks"*) ok "estimate.sh: タスク数が出る" ;; *) ng "estimate.sh: タスク数が出ない: $est" ;; esac
"$EVALS/estimate.sh" --reps >/dev/null 2>&1
check_eq "estimate.sh: 値の無い旗は exit 2" 2 "$?"

# --- 本番に出ていない ------------------------------------------------------------
check_eq "dry の実行が一時ディレクトリを残さない" 0 "$(find "$TMPDIR" -mindepth 1 -maxdepth 1 | wc -l | tr -d ' ')"

exit "$fail"
