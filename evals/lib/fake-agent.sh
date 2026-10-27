#!/usr/bin/env bash
# dry モードの代役。`claude` / `omp` として PATH の先頭に置かれ、モデルを呼ばずに決まった動きをする。
#
#   fake-agent.sh <claude|omp> <本物と同じ引数...>
#
# run.sh は本番と同じコマンド行を組み立てて実行する。ここでは、その引数が本物の CLI として成り立つか
# （-p とプロンプトがある、omp は --session-dir と --cwd がある、claude は stream-json）を確かめ、
# シナリオの動き（git / 偽 gh の操作）をサンドボックスの中で実際に行い、ハーネスごとの本物の形式で出力する。
# これで run.sh → 出力の読み取り → 採点 → results.jsonl の配線を、モデル無しで通せる。
#
# 動きは EVAL_DRY_SCENARIO で選ぶ:
#   pass     evals/scenarios/<scenario>/pass.sh（正しい動き）
#   violate  タスクの `violation` が指す evals/scenarios/violations/<name>.sh（逸脱した動き）。無ければ何もしない
set -uo pipefail

harness="${1:-}"
shift || true

die() {
    echo "fake-agent($harness): $*" >&2
    exit 2
}

prompt=""
session_dir=""
cwd=""
out_format=""
print_mode=0
# claude / omp とも -p（--print）は真偽値のフラグで、プロンプトは位置引数（--help で確認）。
# 値を取るフラグの値をプロンプトと取り違えないよう、値を取るものを列挙する。
while [[ $# -gt 0 ]]; do
    case "$1" in
    -p | --print)
        print_mode=1
        shift
        ;;
    --session-dir=*)
        session_dir="${1#*=}"
        shift
        ;;
    --cwd=*)
        cwd="${1#*=}"
        shift
        ;;
    --model=* | --approval-mode=* | --mode=*) shift ;;
    --session-dir)
        session_dir="${2:-}"
        shift $(($# >= 2 ? 2 : 1))
        ;;
    --cwd)
        cwd="${2:-}"
        shift $(($# >= 2 ? 2 : 1))
        ;;
    --output-format)
        out_format="${2:-}"
        shift $(($# >= 2 ? 2 : 1))
        ;;
    --model | --max-time | --permission-mode | --approval-mode | --add-dir | --mode)
        shift $(($# >= 2 ? 2 : 1))
        ;;
    -*) shift ;;
    *)
        prompt="$1"
        shift
        ;;
    esac
done
[[ "$print_mode" -eq 1 ]] || die "-p（非対話）が無い"
[[ -n "$prompt" ]] || die "プロンプトが無い"
state="${EVAL_STATE:?EVAL_STATE が未設定です}"
task="${EVAL_TASK:?EVAL_TASK が未設定です}"
case "$harness" in
claude) [[ "$out_format" == stream-json ]] || die "--output-format stream-json が必要" ;;
omp)
    [[ -n "$session_dir" ]] || die "--session-dir が必要（使用量とサブエージェントを読むため）"
    [[ -n "$cwd" ]] || die "--cwd が必要"
    ;;
*) die "未知のハーネス: $harness" ;;
esac
printf '%s' "$prompt" >"$state/dry-prompt.txt"

# --- シナリオの動き -------------------------------------------------------------
events="$state/dry-events.jsonl"
: >"$events"
repo="${cwd:-$PWD}"
cd "$repo" || die "作業ディレクトリへ移れない: $repo"
scen="$(jq -r '.scenario // ""' "$task")"
skill="$(jq -r '.skill // ""' "$task")"
SCEN="$EVALS_DIR/scenarios/$scen"
DRY_NO_DEFAULT_EVENTS=""
final_text=""

ev() { # ev <tool> [agent] [cmd]
    jq -nc --arg tool "$1" --arg agent "${2:-}" --arg cmd "${3:-}" \
        '{owner: "main", tool: $tool, agent: (if $agent == "" then null else $agent end), cmd: (if $cmd == "" then null else $cmd end)}' >>"$events"
}
x() { # x <コマンド...> : bash イベントとして記録して実行する
    ev bash "" "$*"
    "$@"
}
final() { final_text="$1"; }
# issue_no <N> : タスクの中の Issue 番号（1 始まり）を、実際の番号にする（試験用 repo では issue-map.json の番号。ローカルはそのまま）
issue_no() {
    if [[ -n "${EVAL_ISSUE_MAP:-}" ]]; then jq -r --argjson i "$1" '.[$i - 1] // empty' <<<"$EVAL_ISSUE_MAP"; else echo "$1"; fi
}
# 空の名前を stranger にする（empty-name 系のシナリオの修正）
sed_greet() {
    sed 's/echo "Hello, \$1"/echo "Hello, ${1:-stranger}"/' app.sh >app.sh.new && mv app.sh.new app.sh
}
# 回帰テストを足す（CLAUDE.md の「バグ修正は回帰テスト必須」）
add_empty_name_test() {
    mkdir -p tests
    echo 't "greet: 空の名前は stranger" "Hello, stranger" "$(greet "")"' >tests/10_greet_empty.sh
}
dry_wait_checks() {
    [[ -z "${DRY_NO_WAIT:-}" ]] || return 0
    local i
    for i in 1 2 3 4 5; do
        x gh pr checks && return 0
    done
}
# dry_pr <branch> <title> <body> : base（既定 main。試験用 repo ではシナリオの base）から切って、コミット・push・PR 作成・CI 待ちまで行う。
# 試験用 repo では、ブランチ名を EVAL_BRANCH_PREFIX（eval/<run>/）で始める（reset.sh が片付けられる名前にするため）
dry_pr() {
    local branch="${EVAL_BRANCH_PREFIX:-}$1"
    x git checkout -q -b "$branch" "${EVAL_BASE:-main}"
    x git add -A
    x git commit -q -m "$2"
    x git push -q origin HEAD
    x gh pr create --base "${EVAL_BASE:-main}" --head "$branch" --title "$2" --body "$3"
    dry_wait_checks
}
add_farewell() {
    printf '%s\n' 'farewell() { echo "Goodbye, ${1:-stranger}"; }' >>app.sh
    mkdir -p tests
    printf '%s\n' 't "farewell: 名前あり" "Goodbye, Ana" "$(farewell Ana)"' 't "farewell: 空は stranger" "Goodbye, stranger" "$(farewell "")"' >tests/20_farewell.sh
}
fix_readme_typo() {
    printf '# fixture\n\n## Usage\n\n`. ./app.sh; greet Ana`\n' >README.md
}
# dry_pr_merge <branch> <title> <body> -- <編集の関数...> : base から切り、編集・コミット・push・PR 作成・CI 待ち・マージ（偽 gh は記録して、head ブランチを消す）まで行う
dry_pr_merge() {
    local branch="${EVAL_BRANCH_PREFIX:-}$1" title="$2" body="$3" f
    shift 4
    x git checkout -q -b "$branch" "${EVAL_BASE:-main}"
    for f in "$@"; do "$f"; done
    x git add -A
    x git commit -q -m "$title"
    x git push -q origin HEAD
    x gh pr create --base "${EVAL_BASE:-main}" --head "$branch" --title "$title" --body "$body"
    dry_wait_checks
    x gh pr merge "$branch" --merge --delete-branch
    x git checkout -q "${EVAL_BASE:-main}"
}
# dry_sweep_state <queue_total> <prs> : .sweep/state.json を terminal にして閉じる（PR にできなかった分は failed）。
# DRY_TERMINAL_EARLY のときは、キューが 2 件残ったまま terminal にする（WATCHDOG の逸脱）。
dry_sweep_state() {
    local remaining=0
    [[ -z "${DRY_TERMINAL_EARLY:-}" ]] || remaining=2
    mkdir -p .sweep
    jq -n --argjson total "$1" --argjson prs "$2" --argjson rem "$remaining" \
        '{skill: "issue-sweep", phase: "terminal", queue_total: $total, queue_remaining: $rem, processed_count: ($total - $rem), merged_count: $prs, failed_count: ($total - $prs), round: 1, max_rounds: 3, termination_reason: "queue_empty"}' >.sweep/state.json
}

default_events() {
    ev skill "" "$skill"
    case "$skill" in
    impl | impl-wt)
        ev task plan
        ev task develop
        ev task review
        ev bash "" ".claude/skills/impl/scripts/verify-scope.sh --type fix --issue 1"
        ;;
    refine | refine-git | refine-sweep)
        ev task review
        ;;
    issue-sweep)
        ev task develop
        ev task develop
        ev task review
        ev task review
        ;;
    esac
}

script=""
if [[ "${EVAL_DRY_SCENARIO:-pass}" == violate ]]; then
    violation="$(jq -r '.violation // ""' "$task")"
    [[ -z "$violation" ]] || script="$EVALS_DIR/scenarios/violations/$violation.sh"
else
    script="$SCEN/pass.sh"
fi
if [[ -n "$script" ]]; then
    [[ -f "$script" ]] || die "シナリオのスクリプトが無い: $script"
    # シナリオ内の失敗（コマンドの打ち間違い・前提の崩れ）を見逃すと、採点が「逸脱を検出した」ように見えてしまう。
    # set -e で止めて、ハーネスのエラーとして出す。
    set -e
    # shellcheck source=/dev/null
    . "$script" >>"$state/dry-agent.log" 2>&1
    set +e
fi
[[ -n "$DRY_NO_DEFAULT_EVENTS" ]] || default_events >>"$events"

# --- 本物の形式で出力 -------------------------------------------------------------
# 1 イベント = 1 回のモデル呼び出し（入力 1000 / 出力 20）。task イベントには、そのサブエージェントの呼び出しを 1 回足す。
emit_claude() {
    jq -nc --slurpfile ev "$events" --arg final "$final_text" '
      def tname: ({ask: "AskUserQuestion", task: "Task", bash: "Bash", read: "Read", edit: "Edit", write: "Write", skill: "Skill"}[.] // .);
      def usage: {input_tokens: 100, output_tokens: 20, cache_read_input_tokens: 900, cache_creation_input_tokens: 0};
      {type: "system", subtype: "init", model: "fake"},
      ($ev | to_entries[] | .key as $i | .value as $e
        | {type: "assistant", parent_tool_use_id: null,
           message: {id: "msg_\($i)", model: "fake", usage: usage,
                     content: [{type: "tool_use", id: "toolu_\($i)", name: ($e.tool | tname),
                                input: (if $e.tool == "task" then {subagent_type: $e.agent, description: "dry", prompt: "dry"}
                                        elif $e.tool == "bash" then {command: $e.cmd}
                                        elif $e.tool == "skill" then {skill: $e.cmd}
                                        else {} end)}]}},
          (if $e.tool == "task" then {type: "assistant", parent_tool_use_id: "toolu_\($i)", message: {id: "msg_sub_\($i)", model: "fake", usage: usage, content: [{type: "text", text: "done"}]}} else empty end)),
      {type: "assistant", parent_tool_use_id: null, message: {id: "msg_final", model: "fake", usage: usage, content: [{type: "text", text: $final}]}},
      {type: "result", subtype: "success", is_error: false, result: $final}'
}

emit_omp() {
    local main="$session_dir/main.jsonl" subdir="$session_dir/main"
    mkdir -p "$subdir"
    jq -nc --slurpfile ev "$events" --arg final "$final_text" '
      def usage: {input: 100, output: 20, cacheRead: 900, cacheWrite: 0};
      {type: "session", version: 3, id: "dry-main", cwd: "."},
      {type: "model_change", model: "fake"},
      ($ev | to_entries[] | .key as $i | .value as $e
        | {type: "message", message: {role: "assistant", usage: usage,
             content: [{type: "toolCall", id: "t\($i)", name: $e.tool,
                        arguments: (if $e.tool == "task" then {tasks: [{agent: $e.agent, name: "Dry\($e.agent)\($i)", task: "dry"}]}
                                    elif $e.tool == "bash" then {command: $e.cmd}
                                    else {} end)}]}}),
      {type: "message", message: {role: "assistant", usage: usage, content: [{type: "text", text: $final}]}}' >"$main"
    local i=0 line agent
    while IFS= read -r line; do
        agent="$(jq -r 'select(.tool == "task") | .agent' <<<"$line")"
        if [[ -n "$agent" ]]; then
            jq -nc --arg parent "$main" '{type: "session", version: 3, id: "dry-sub", parentSession: $parent}, {type: "message", message: {role: "assistant", usage: {input: 100, output: 20, cacheRead: 900, cacheWrite: 0}, content: [{type: "text", text: "done"}]}}' >"$subdir/Dry$agent$i.jsonl"
        fi
        i=$((i + 1))
    done <"$events"
}

case "$harness" in
claude) emit_claude ;;
omp) emit_omp ;;
esac
