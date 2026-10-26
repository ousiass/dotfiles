#!/usr/bin/env bash
# e2e eval の実行。タスク 1 件 × rep 1 回ごとに、使い捨てのサンドボックスを作り、ハーネス（claude / omp）を
# 非対話で動かし、採点して results.jsonl に 1 行足す。
#
#   evals/run.sh --harness claude|omp --dry [--out DIR] [--rep N] [--task ID]... [--violate]
#   evals/run.sh --harness claude|omp --live --model ID [--out DIR] [--rep N] [--task ID]...   （有料。下記）
#
#   --harness  claude（`claude -p`）か omp（`omp -p`）。同じタスクを同じ採点で通す
#   --dry      モデルを呼ばない。claude / omp の代わりに evals/lib/fake-agent.sh を PATH の先頭に置き、
#              コマンド行・出力の読み取り・採点・results.jsonl までを本番と同じ経路で通す
#   --violate  dry で、正しい動きではなく、タスクの violations（WATCHDOG の逸脱）をする。採点が検出することの確認用
#   --live     本物のモデルを呼ぶ（課金される）。EVAL_CONFIRM_PAID=1 を付けないと止まる。--model が必須
#   --out      出力先（既定 evals/results/<日時>-<harness>-<dry|live>）。results.jsonl と run.json ができる
#   --rep      1 タスクあたりの回数（既定 2。issue の運用ルール: 2 rep 以上）
#   --task     タスク id を絞る（複数可）
#   --remote   ローカルの使い捨て repo と偽 gh ではなく、試験用 repo（ousiass/dotfiles-eval-sandbox。名前は固定）に実際に書かせる。
#              エージェントの git push と gh（記録用ラッパー lib/gh-record.sh 経由）だけが書き込む。run.sh 自身は書き込まない。
#              初期状態から動いていたら、その実行は始めない（reset.sh --apply と seed.sh は人が実行する。自動では走らせない）。
#              dry では、試験用 repo の代わりにローカルの bare repo（seed.sh で同じ内容を入れる）と偽 gh を使う（ネットワークに出ない）。
#              live では GH_TOKEN（試験用 repo だけに書ける fine-grained トークン。evals/sandbox/README.md）が要る
#
# 既定のサンドボックスは $TMPDIR（無ければ /tmp）の下にだけ作る。本番の GitHub には、偽の gh（PATH の先頭）を通すので出ない。
# 本物の gh を絶対パスで呼ばれるとこの保証は崩れる。live は、使い捨ての VM かコンテナの中で動かすこと。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export EVALS_DIR
# 隔離フォルダの git 設定（<root>/with-env が設定する）。fixture.sh がホストの設定を切り離す前に控えておく（--remote --live で使う）
ORIG_GIT_CONFIG_GLOBAL="${GIT_CONFIG_GLOBAL:-}"
# shellcheck source=lib/fixture.sh
. "$EVALS_DIR/lib/fixture.sh"
# shellcheck source=lib/adapt.sh
. "$EVALS_DIR/lib/adapt.sh"
# shellcheck source=lib/remote.sh
. "$EVALS_DIR/lib/remote.sh"

remote=0
# remote.sh の remote_prepare が決める値（--remote のとき）
r_base="" r_prefix="" r_map="" r_gh_real=""
harness=""
mode=""
model="${EVAL_MODEL:-}"
out=""
reps=2
violate=0
only=()
while [[ $# -gt 0 ]]; do
    # 値を取る旗に値が無いとき、shift 2 が失敗して無限ループになるのを防ぐ
    case "$1" in
    --harness | --model | --out | --rep | --task)
        [[ $# -ge 2 ]] || {
            echo "run.sh: $1 に値が必要です" >&2
            exit 2
        }
        ;;
    esac
    case "$1" in
    --harness)
        harness="${2:-}"
        shift 2
        ;;
    --dry)
        mode=dry
        shift
        ;;
    --live)
        mode=live
        shift
        ;;
    --violate)
        violate=1
        shift
        ;;
    --model)
        model="${2:-}"
        shift 2
        ;;
    --out)
        out="${2:-}"
        shift 2
        ;;
    --rep)
        reps="${2:-}"
        shift 2
        ;;
    --task)
        only+=("${2:-}")
        shift 2
        ;;
    --remote)
        remote=1
        shift
        ;;
    -h | --help)
        sed -n '2,23p' "${BASH_SOURCE[0]}"
        exit 0
        ;;
    *)
        echo "run.sh: 不明な引数: $1" >&2
        exit 2
        ;;
    esac
done
case "$harness" in claude | omp) ;; *)
    echo "run.sh: --harness は claude か omp" >&2
    exit 2
    ;;
esac
[[ -n "$mode" ]] || {
    echo "run.sh: --dry か --live を指定してください" >&2
    exit 2
}
[[ "$reps" =~ ^[1-9][0-9]*$ ]] || {
    echo "run.sh: --rep は 1 以上の整数" >&2
    exit 2
}
if [[ "$mode" == live ]]; then
    [[ -n "$model" ]] || {
        echo "run.sh: --live は --model（固定するモデル id）が必須です" >&2
        exit 2
    }
    [[ "${EVAL_CONFIRM_PAID:-}" == 1 ]] || {
        echo "run.sh: --live は課金されます。規模は evals/estimate.sh で確認し、実行するなら EVAL_CONFIRM_PAID=1 を付けてください" >&2
        exit 2
    }
    # 隔離フォルダ（evals/sandbox/init.sh が作る <root>/with-env）の外では、本物の HOME・設定・gh のログインで動いてしまう
    [[ -n "${EVAL_SANDBOX_ROOT:-}" && "${HOME:-}" == "$EVAL_SANDBOX_ROOT"/* && "${CLAUDE_CONFIG_DIR:-}" == "$EVAL_SANDBOX_ROOT"/* && "${PI_CODING_AGENT_DIR:-}" == "$EVAL_SANDBOX_ROOT"/* ]] || {
        echo "run.sh: --live は隔離フォルダの中でだけ動かします。<root>/with-env を通してください（evals/sandbox/README.md）" >&2
        exit 2
    }
    [[ "$violate" -eq 0 ]] || {
        echo "run.sh: --violate は --dry でだけ使えます" >&2
        exit 2
    }
fi
command -v jq >/dev/null || {
    echo "run.sh: jq が必要です" >&2
    exit 2
}

[[ -n "$out" ]] || out="${EVAL_RESULTS_DIR:-$EVALS_DIR/results}/$(date +%Y%m%d-%H%M%S)-$harness-$mode"
mkdir -p "$out"
results="$out/results.jsonl"
: >"$results"

tasks="$EVALS_DIR/tasks.jsonl"
root="$(mktemp -d "${TMPDIR:-/tmp}/eval-run.XXXXXX")"
# EVAL_KEEP=1 のときはサンドボックスを残して場所を出す（採点が意図どおりか調べるとき用）
trap '[[ -n "${EVAL_KEEP:-}" ]] && echo "run.sh: サンドボックスを残した: $root" >&2 || rm -rf "$root"' EXIT

started="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
harness_errors=0
n_runs=0
repo_mode=local
[[ "$remote" -eq 0 ]] || repo_mode=remote
if [[ "$remote" -eq 1 ]]; then
    remote_init || exit 1
fi

# 本番の呼び出し。claude / omp のどちらも -p は真偽値で、プロンプトは最後の位置引数（--help で確認）。
# 値を固定するため、--model は必ず渡す（dry では無視される）。
agent_cmd() { # <harness> <repo> <session-dir> <prompt>
    case "$1" in
    claude)
        printf '%s\0' claude -p --output-format stream-json --verbose --dangerously-skip-permissions --no-session-persistence ${model:+--model "$model"} "$4"
        ;;
    omp)
        # omp の --help は値つきの旗を --flag=<value> の形で示している。その形に合わせる
        printf '%s\0' omp -p "--cwd=$2" "--session-dir=$3" --approval-mode=yolo ${model:+"--model=$model"} "$4"
        ;;
    esac
}

with_timeout() { # 秒数を超えたら止める。timeout / gtimeout が無ければそのまま実行する
    local secs="$1"
    shift
    if command -v timeout >/dev/null; then
        timeout "$secs" "$@"
    elif command -v gtimeout >/dev/null; then
        gtimeout "$secs" "$@"
    else
        "$@"
    fi
}

run_one() { # <task-json-line> <rep>
    local line="$1" rep="$2" id sb taskfile prompt cmd=() status=ok t0 t1 raw norm graded summary acts
    id="$(jq -r .id <<<"$line")"
    n_runs=$((n_runs + 1))
    sb="$root/run-$n_runs"
    taskfile="$sb.task.json"
    printf '%s\n' "$line" >"$taskfile"
    if [[ "$remote" -eq 1 ]]; then
        if ! remote_prepare "$sb" "$taskfile" "$n_runs"; then
            echo "run.sh: ${id} rep${rep}: 試験用 repo の準備ができない（上の理由。何も書き込んでいない）" >&2
            harness_errors=$((harness_errors + 1))
            jq -nc --arg id "$id" --argjson rep "$rep" --arg harness "$harness" --arg mode "$mode" --arg model "$model" \
                '{prompt_id: $id, rep: $rep, harness: $harness, mode: $mode, model: (if $model == "" then null else $model end), status: "error"}' >>"$results"
            return
        fi
        prompt="$(remote_prompt "$(jq -r .prompt <<<"$line")" "$r_base" "$r_prefix" "$r_map")"
    else
        if ! fixture_make "$sb" "$taskfile"; then
            echo "run.sh: $id rep$rep: サンドボックスを作れない" >&2
            harness_errors=$((harness_errors + 1))
            return
        fi
        prompt="$(jq -r .prompt <<<"$line")"
    fi
    mkdir -p "$sb/sessions"
    while IFS= read -r -d '' a; do cmd+=("$a"); done < <(agent_cmd "$harness" "$sb/repo" "$sb/sessions" "$prompt")

    local path="$sb/bin:$PATH"
    if [[ "$mode" == dry ]]; then
        # PATH の解決に頼らず、fake-agent.sh を直接呼ぶ（本物の claude / omp を呼ばない保証を、PATH の並びに預けない）。
        # 引数は本番のコマンド行のまま渡す（先頭の claude / omp だけを置き換える）
        cmd=(bash "$EVALS_DIR/lib/fake-agent.sh" "$harness" "${cmd[@]:1}")
    fi
    raw="$sb/agent.out"
    t0=$SECONDS
    (
        cd "$sb/repo" || exit 1
        export PATH="$path" EVAL_STATE="$sb/state" EVAL_TASK="$taskfile" CLAUDE_PROJECT_DIR="$sb/repo"
        if [[ "$remote" -eq 1 ]]; then
            # 記録用の gh ラッパー（$sb/bin/gh）が呼ぶ先と、シナリオの base・ブランチ名の約束。dry の偽エージェントも同じ値を読む
            export EVAL_GH_REAL="$r_gh_real" EVAL_BASE="$r_base" EVAL_BRANCH_PREFIX="$r_prefix" EVAL_ISSUE_MAP="$r_map"
            # live は、エージェントの git が隔離した HOME の .gitconfig（identity と gh の credential helper）を読む
            [[ "$mode" == dry ]] || export GIT_CONFIG_GLOBAL="$ORIG_GIT_CONFIG_GLOBAL"
        fi
        if [[ "$mode" == dry ]]; then
            export EVAL_DRY_SCENARIO=pass
            [[ "$violate" -eq 0 ]] || EVAL_DRY_SCENARIO=violate
        fi
        with_timeout "${EVAL_TIMEOUT_S:-3600}" "${cmd[@]}" >"$raw" 2>"$sb/agent.err"
    )
    local rc=$?
    t1=$SECONDS
    [[ "$rc" -eq 0 ]] || status=error

    norm="$sb/norm.json"
    if [[ "$status" == ok ]]; then
        case "$harness" in
        claude) adapt_claude "$raw" >"$norm" 2>"$sb/adapt.err" || status=error ;;
        omp) adapt_omp "$sb/sessions" >"$norm" 2>"$sb/adapt.err" || status=error ;;
        esac
    fi
    # 使用量がひとつも取れていない行を ok にすると、基準値が 0 トークンで汚れる。ハーネスのエラーとして残す
    if [[ "$status" == ok && "$(jq '.calls | length' "$norm")" -eq 0 ]]; then
        status=error
        echo "モデル呼び出しの使用量が 1 件も取れなかった（$harness の出力形式の想定が外れている）" >"$sb/adapt.err"
    fi
    if [[ "$status" != ok ]]; then
        # ハーネスのエラーは、採点せずに status=error で残す（compare.py は status!=ok の行を数えない）
        harness_errors=$((harness_errors + 1))
        echo "run.sh: ${id} rep${rep}: ハーネスのエラー（exit ${rc}）: $(head -c 300 "$sb/agent.err" "$sb/adapt.err" 2>/dev/null | tr '\n' ' ')" >&2
        jq -nc --arg id "$id" --argjson rep "$rep" --arg harness "$harness" --arg mode "$mode" --arg model "$model" \
            '{prompt_id: $id, rep: $rep, harness: $harness, mode: $mode, model: (if $model == "" then null else $model end), status: "error"}' >>"$results"
        return
    fi
    if [[ "$remote" -eq 1 ]] && ! remote_extract "$sb"; then
        harness_errors=$((harness_errors + 1))
        echo "run.sh: ${id} rep${rep}: 試験用 repo の状態を取り出せない" >&2
        jq -nc --arg id "$id" --argjson rep "$rep" --arg harness "$harness" --arg mode "$mode" --arg model "$model" \
            '{prompt_id: $id, rep: $rep, harness: $harness, mode: $mode, model: (if $model == "" then null else $model end), status: "error"}' >>"$results"
        return
    fi
    graded="$("$EVALS_DIR/grade.sh" "$sb" "$taskfile" "$norm")" || {
        harness_errors=$((harness_errors + 1))
        echo "run.sh: $id rep$rep: 採点に失敗" >&2
        jq -nc --arg id "$id" --argjson rep "$rep" --arg harness "$harness" --arg mode "$mode" --arg model "$model" \
            '{prompt_id: $id, rep: $rep, harness: $harness, mode: $mode, model: (if $model == "" then null else $model end), status: "error"}' >>"$results"
        return
    }
    summary="$(norm_summary <"$norm")"
    # 書き込みの動き（compare.py の actions）: 状態を変える gh の呼び出し
    acts="$(jq -sc '
        [ .[] | select(.cmd | test("^gh (pr (create|merge|edit|comment|close|ready|review)|issue (create|comment|edit|close|reopen))")) | {name: (.cmd | split(" ") | .[0:3] | join(" "))} ]' "$sb/state/actions.jsonl")"
    # 止められた（unsupported）・失敗した（error / fail）gh の呼び出し。state は実行後に消えるので、原因を後から調べられるように残す
    problems="$(jq -sc '[ .[] | select(.result == "unsupported" or .result == "error" or .result == "fail") | {cmd: (.cmd | split(" ") | .[0:4] | join(" ")), result: .result, why: (.why // null)} ]' "$sb/state/actions.jsonl")"
    jq -nc --argjson task "$line" --argjson g "$graded" --argjson s "$summary" --argjson acts "$acts" --argjson problems "$problems" \
        --arg harness "$harness" --arg mode "$mode" --arg repo "$repo_mode" --argjson rep "$rep" --argjson lat "$((t1 - t0))" \
        --arg model "$(jq -r '.model // empty' "$norm")" --arg fixed "$model" '
        {prompt_id: $task.id, rep: $rep, harness: $harness, mode: $mode, repo: $repo,
         tags: (["skill:" + $task.skill] + ($task.breaks // []) + [($task.watchdog // [])[] | "watchdog:" + tostring]),
         status: "ok", grade: $g.grade, checks: $g.checks, failed: $g.failed,
         latency_s: $lat, in_tokens: $s.in_tokens, out_tokens: $s.out_tokens, model_calls: $s.model_calls, by_agent: $s.by_agent,
         actions: $acts, gh_problems: $problems, model: (if $model != "" then $model elif $fixed != "" then $fixed else null end)}' >>"$results"
}

selected=0
while IFS= read -r line; do
    [[ -n "$line" ]] || continue
    id="$(jq -r .id <<<"$line")"
    if [[ "${#only[@]}" -gt 0 ]]; then
        match=0
        for o in "${only[@]}"; do [[ "$o" == "$id" ]] && match=1; done
        [[ "$match" -eq 1 ]] || continue
    fi
    selected=$((selected + 1))
    if [[ "$violate" -eq 1 ]]; then
        # 逸脱ごとに 1 回（rep は使わない）。どの逸脱かを results に残すため、violation を task に差し込んで実行する
        while IFS= read -r v; do
            [[ -n "$v" ]] || continue
            run_one "$(jq -c --arg v "$v" '.violation = $v | .id = (.id + "@" + $v)' <<<"$line")" 1
        done < <(jq -r '.violations[]?' <<<"$line")
    else
        for ((r = 1; r <= reps; r++)); do run_one "$line" "$r"; done
    fi
done <"$tasks"
[[ "$selected" -gt 0 ]] || {
    echo "run.sh: 対象のタスクが無い" >&2
    exit 2
}

ended="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
jq -n --arg harness "$harness" --arg mode "$mode" --arg model "$model" --arg started "$started" --arg ended "$ended" \
    --arg commit "$(git -C "$EVALS_DIR" rev-parse HEAD 2>/dev/null || echo unknown)" --arg args "$*" \
    --argjson runs "$n_runs" --argjson errors "$harness_errors" --argjson reps "$reps" --argjson violate "$violate" '
    {harness: $harness, mode: $mode, model: (if $model == "" then null else $model end), commit: $commit, args: $args,
     started_at: $started, ended_at: $ended, runs: $runs, harness_errors: $errors, reps: $reps, violate: ($violate == 1)}' >"$out/run.json"
echo "run.sh: ${harness}/${mode} 完了: ${n_runs} 回、ハーネスエラー ${harness_errors}（${results}）"
[[ "$harness_errors" -eq 0 ]]
