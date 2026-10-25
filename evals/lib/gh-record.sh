#!/usr/bin/env bash
# 試験用 repo に書き込む実行（run.sh --remote）で、エージェントの PATH 先頭に `gh` として置く記録用のラッパー。
#
# 1. 固定の試験用 repo（evals/sandbox/lib.sh の SANDBOX_REPO）以外には動かさない
#      --repo / -R・GH_REPO・gh api のパスが別の repo を指していたら、実行せずに止める
#      許す subcommand を絞る（auth status|git-credential、api、issue、pr、label、repo view、run）。ほかは止める
# 2. 呼び出しを $EVAL_STATE/actions.jsonl に 1 行 1 JSON で記録する（採点が「書き込みの動き」として読む）
#      result: gh pr checks は exit 0 = pass / 8 = pending / それ以外 = fail。ほかは exit 0 = ok / それ以外 = error。止めたものは unsupported
# 3. gh pr create と gh issue create には、ラベル eval を足す（reset.sh が eval ラベルの PR・Issue だけを片付ける）
# 4. 本物の gh（$EVAL_GH_REAL）に渡す。EVAL_GH_REAL は必須（PATH からは探さない。自分自身を呼ぶ無限ループを避ける）。
#    dry では、EVAL_GH_REAL に偽の gh（evals/lib/fake-gh.sh を呼ぶもの）が入る。本物の gh は呼ばない
#
# gh auth git-credential は、git の credential helper としてのやりとり（トークンが標準出力に出る）なので、記録しない。
set -uo pipefail

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../sandbox/lib.sh
. "$here/../sandbox/lib.sh"

real="${EVAL_GH_REAL:?EVAL_GH_REAL が未設定です（本物の gh か、dry の偽 gh）}"
state="${EVAL_STATE:?EVAL_STATE が未設定です}"
actions="$state/actions.jsonl"

# log_call <result> <gh に渡された引数...> : 呼び出しを 1 行 1 JSON で残す
log_call() {
    local result="$1"
    shift
    jq -nc --arg cmd "gh $*" --arg result "$result" '{cmd: $cmd, result: $result}' >>"$actions"
}
refuse() { # refuse <理由> <引数...>
    local why="$1"
    shift
    jq -nc --arg cmd "gh $*" --arg result "unsupported" --arg why "$why" '{cmd: $cmd, result: $result, why: $why}' >>"$actions"
    echo "gh（eval のラッパー）: ${why}。この環境では ${SANDBOX_REPO} だけを操作できます" >&2
    exit 1
}

# 認証のやりとり（git の credential helper）は素通し
if [[ "${1:-}" == auth && "${2:-}" == git-credential ]]; then
    exec "$real" "$@"
fi

args=("$@")

# --- repo の指定 -----------------------------------------------------------------------
if [[ -n "${GH_REPO:-}" && "$GH_REPO" != "$SANDBOX_REPO" && "$GH_REPO" != "github.com/$SANDBOX_REPO" ]]; then
    refuse "GH_REPO が別の repo（${GH_REPO}）を指している" "${args[@]}"
fi
prev=""
for a in "${args[@]}"; do
    val=""
    case "$prev" in --repo | -R) val="$a" ;; esac
    case "$a" in --repo=*) val="${a#--repo=}" ;; esac
    if [[ -n "$val" && "$val" != "$SANDBOX_REPO" && "$val" != "github.com/$SANDBOX_REPO" ]]; then
        refuse "--repo が別の repo（${val}）を指している" "${args[@]}"
    fi
    # URL の引数（gh pr view https://github.com/o/r/pull/1 など）は GH_REPO より優先されるので、別の repo のものは止める
    case "$a" in
    http://* | https://* | github.com/*)
        [[ "$a" =~ ^(https?://)?(api\.)?github\.com/(repos/)?"$SANDBOX_REPO"(\.git)?([/?#]|$) ]] || [[ "$a" =~ ^https://api\.github\.com/(graphql|user)?$ ]] ||
            refuse "別の repo の URL を指している（${a}）" "${args[@]}"
        ;;
    esac
    prev="$a"
done

# --- subcommand -------------------------------------------------------------------------
sub="${1:-}"
cmd2="${2:-}"
case "$sub $cmd2" in
"auth status") ;;
"repo view")
    # repo view は位置引数の repo を見る（GH_REPO は効かない）。位置引数があれば固定の repo だけ許し、無ければ固定の repo を足す
    # 値を取る旗（--json など。--flag=value 形式は 1 引数）の次の引数だけを飛ばし、ほかの「-」で始まらない引数は全部、位置引数として検査する
    # （--web ousiass/dotfiles や、owner を省いた dotfiles も止まる）
    positional=0
    prev=""
    for a in "${args[@]:2}"; do
        case "$prev" in
        --json | --jq | -q | --template | -t | --branch | -b) prev=""; continue ;;
        esac
        case "$a" in
        -*) ;;
        *) positional=1; [[ "$a" == "$SANDBOX_REPO" ]] || refuse "gh repo view が別の repo（${a}）を指している" "${args[@]}" ;;
        esac
        prev="$a"
    done
    ;;
"api "*) ;;
"issue "* | "pr " | "pr "* | "label "*) ;;
"run list" | "run view" | "run watch") ;;
*) refuse "許可していない subcommand（gh ${sub} ${cmd2}）" "${args[@]}" ;;
esac
# gh api: パスが別の repo を指していたら止める（GraphQL は --repo の対象外。fine-grained トークンの範囲が最後の砦）
if [[ "$sub" == api ]]; then
    for a in "${args[@]:1}"; do
        case "$a" in
        -*) ;;
        repos/*)
            [[ "$a" == "repos/${SANDBOX_REPO}" || "$a" == "repos/${SANDBOX_REPO}/"* ]] || refuse "gh api のパスが別の repo を指している（${a}）" "${args[@]}"
            ;;
        /repos/*)
            [[ "$a" == "/repos/${SANDBOX_REPO}" || "$a" == "/repos/${SANDBOX_REPO}/"* ]] || refuse "gh api のパスが別の repo を指している（${a}）" "${args[@]}"
            ;;
        esac
    done
fi

# --- ラベル eval を足す ---------------------------------------------------------------------
extra=()
case "$sub $cmd2" in
"pr create" | "issue create")
    has_eval=0
    prev=""
    for a in "${args[@]}"; do
        case "$prev" in --label | -l) [[ ",$a," == *",eval,"* ]] && has_eval=1 ;; esac
        case "$a" in --label=*) [[ ",${a#--label=}," == *",eval,"* ]] && has_eval=1 ;; esac
        prev="$a"
    done
    [[ "$has_eval" -eq 1 ]] || extra=(--label eval)
    ;;
"repo view")
    [[ "$positional" -eq 1 ]] || extra=("$SANDBOX_REPO")
    ;;
esac

# 実行。対象の repo は GH_REPO でも固定する（git の remote に左右されない）
export GH_REPO="$SANDBOX_REPO"
# 空の配列の展開は、bash 3.2（macOS）で set -u に引っかかるので、+ で囲む
"$real" "${args[@]}" ${extra[@]+"${extra[@]}"}
rc=$?
result=error
if [[ "$sub $cmd2" == "pr checks" ]]; then
    case "$rc" in 0) result=pass ;; 8) result=pending ;; *) result=fail ;; esac
elif [[ "$rc" -eq 0 ]]; then
    result=ok
fi
log_call "$result" "${args[@]}"
exit "$rc"
