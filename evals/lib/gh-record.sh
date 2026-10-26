#!/usr/bin/env bash
# 試験用 repo に書き込む実行（run.sh --remote）で、エージェントの PATH 先頭に `gh` として置く記録用のラッパー。
#
# 1. 固定の試験用 repo（evals/sandbox/lib.sh の SANDBOX_REPO）以外には動かさない
#      --repo / -R・GH_REPO・gh api のパスが別の repo を指していたら、実行せずに止める
#      許す subcommand を絞る（auth status|git-credential、api、issue、pr、label、repo view、run）。ほかは止める
# 2. 呼び出しを $EVAL_STATE/actions.jsonl に 1 行 1 JSON で記録する（採点が「書き込みの動き」として読む）
#      result: gh pr checks は Actions の API で置き換える（下の pr_checks）。exit 0 = pass / 8 = pending / それ以外 = fail。ほかは exit 0 = ok / それ以外 = error。止めたものは unsupported
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

# 普段の gh のログイン（ユーザーの gh の設定ディレクトリ）を使う実行: トークンは環境変数にもファイルにも置かない。
# 本物の gh を呼ぶときだけ、この wrapper が GH_CONFIG_DIR をそちらに向けて、GH_TOKEN を外す（エージェントの環境には出ない）
if [[ -n "${EVAL_GH_USER_CONFIG_DIR:-}" ]]; then
    export GH_CONFIG_DIR="$EVAL_GH_USER_CONFIG_DIR"
    unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
fi

# git の credential helper。トークンを渡すのは、固定の repo に対する get だけ。
# 別の repo・別のホスト・path が来ない（credential.useHttpPath が無い）ときは何も返さない（git は認証に失敗する）。store / erase は何もしない
if [[ "${1:-}" == auth && "${2:-}" == git-credential ]]; then
    [[ "${3:-}" == get ]] || exit 0
    req="$(cat)"
    cred_host="$(printf '%s\n' "$req" | sed -n 's/^host=//p' | head -1)"
    cred_path="$(printf '%s\n' "$req" | sed -n 's/^path=//p' | head -1)"
    if [[ "$cred_host" == github.com && ( "$cred_path" == "$SANDBOX_REPO" || "$cred_path" == "${SANDBOX_REPO}.git" ) ]]; then
        printf '%s\n' "$req" | "$real" "$@"
        exit $?
    fi
    jq -nc --arg cmd "git credential get host=${cred_host} path=${cred_path}" --arg result "unsupported" --arg why "固定の repo 以外には認証情報を渡さない" '{cmd: $cmd, result: $result, why: $why}' >>"$actions"
    exit 0
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
"issue transfer") refuse "gh issue transfer は別の repo に Issue を移せるので使えない" "${args[@]}" ;;
"issue "* | "pr " | "pr "* | "label "*) ;;
"run list" | "run view" | "run watch") ;;
*) refuse "許可していない subcommand（gh ${sub} ${cmd2}）" "${args[@]}" ;;
esac
# gh api: 叩ける先は固定の repo（repos/<固定の repo>/...）と user・rate_limit だけ。GraphQL・別の repo・orgs・gists・user/repos などは止める
# （普段の gh のログインのように、試験用 repo 以外にも書けるトークンのとき、gh api が repo の固定をすり抜ける穴になるため）
# エンドポイント = 値を取る旗の値を除いた最初の「-」で始まらない引数
if [[ "$sub" == api ]]; then
    endpoint=""
    prev=""
    for a in "${args[@]:1}"; do
        case "$prev" in
        -X | --method | -H | --header | -f | --raw-field | -F | --field | -q | --jq | -t | --template | --input | -p | --preview | --hostname | --cache) prev=""; continue ;;
        esac
        prev="$a"
        case "$a" in
        -*) ;;
        *)
            endpoint="$a"
            break
            ;;
        esac
    done
    ep="${endpoint#https://api.github.com/}"
    ep="${ep#/}"
    case "$ep" in
    *..* | *%2[eE]* | *%2[fF]* | *\\*) refuse "gh api のパスに .. や %2e を含んでいる（${endpoint}）" "${args[@]}" ;;
    "repos/${SANDBOX_REPO}" | "repos/${SANDBOX_REPO}/"* | "repos/${SANDBOX_REPO}?"*) ;;
    user | user\?* | rate_limit | rate_limit\?*) ;;
    *) refuse "gh api のパスが固定の repo 以外を指している（${endpoint:-なし}）。許すのは repos/${SANDBOX_REPO}/... と user・rate_limit だけ" "${args[@]}" ;;
    esac
fi

# --- gh pr checks を Actions の API に置き換える -----------------------------------------------
# gh pr checks は GraphQL の statusCheckRollup を読むが、fine-grained トークンには Checks・Commit statuses の権限が無く FORBIDDEN になる。
# 代わりに、PR の先端（gh pr view の headRefOid）の Actions の run（actions/runs?head_sha=）を読んで、gh pr checks と同じ終了コードにする:
# 0 = 全部成功（skipped・neutral を含む）、1 = 失敗がある（run が 1 つも無いときも 1。gh と同じ）、8 = 実行中が残っている（失敗が無いとき）
# 対応する旗: --watch、-i / --interval N、--fail-fast・--required（無視）。位置引数は PR の番号・ブランチ・URL
pr_checks() {
    local sel="" watch=0 interval=10 i a prev="" view sha runs rows rc n_total n_fail n_pending
    for ((i = 2; i < ${#args[@]}; i++)); do
        a="${args[$i]}"
        case "$prev" in
        -i | --interval)
            interval="$a"
            prev=""
            continue
            ;;
        esac
        case "$a" in
        --watch) watch=1 ;;
        -i | --interval) prev="$a" ;;
        --interval=*) interval="${a#--interval=}" ;;
        --fail-fast | --required) ;;
        -*) refuse "gh pr checks の旗 ${a} には対応していない（--watch・--interval・--fail-fast・--required だけ）" "${args[@]}" ;;
        *) sel="$a" ;;
        esac
    done
    [[ "$interval" =~ ^[0-9]+$ ]] || refuse "gh pr checks の --interval が数字ではない（${interval}）" "${args[@]}"
    export GH_REPO="$SANDBOX_REPO"
    while :; do
        if ! view="$("$real" pr view ${sel:+"$sel"} --json headRefOid,headRefName 2>&1)"; then
            printf '%s\n' "$view" >&2
            log_call fail "${args[@]}"
            exit 1
        fi
        sha="$(jq -r '.headRefOid // empty' <<<"$view")"
        if [[ -z "$sha" ]] || ! runs="$("$real" api "repos/${SANDBOX_REPO}/actions/runs?head_sha=${sha}&per_page=100" 2>&1)"; then
            printf '%s\n' "${runs:-$view}" >&2
            log_call fail "${args[@]}"
            exit 1
        fi
        rows="$(jq -r '.workflow_runs[]? | (.conclusion // "") as $c | [.name, (if .status != "completed" then "pending" elif (["success", "skipped", "neutral"] | index($c)) != null then "pass" else "fail" end), "", .html_url] | @tsv' <<<"$runs")"
        n_total="$(printf '%s' "$rows" | grep -c . || true)"
        n_fail="$(printf '%s' "$rows" | awk -F'\t' '$2 == "fail"' | grep -c . || true)"
        n_pending="$(printf '%s' "$rows" | awk -F'\t' '$2 == "pending"' | grep -c . || true)"
        if [[ "$n_total" -eq 0 ]]; then
            echo "no checks reported on the '$(jq -r '.headRefName // empty' <<<"$view")' branch" >&2
            rc=1
        else
            printf '%s\n' "$rows"
            if [[ "$n_fail" -gt 0 ]]; then rc=1; elif [[ "$n_pending" -gt 0 ]]; then rc=8; else rc=0; fi
        fi
        if [[ "$watch" -eq 1 && "$rc" -eq 8 ]]; then
            sleep "$interval"
            continue
        fi
        break
    done
    case "$rc" in 0) log_call pass "${args[@]}" ;; 8) log_call pending "${args[@]}" ;; *) log_call fail "${args[@]}" ;; esac
    exit "$rc"
}
[[ "$sub $cmd2" == "pr checks" ]] && pr_checks

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
[[ "$rc" -eq 0 ]] && result=ok
log_call "$result" "${args[@]}"
exit "$rc"
