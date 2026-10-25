#!/usr/bin/env bash
# eval 用の偽 gh。本物の GitHub には一切つながらない。
#
# サンドボックス（evals/lib/fixture.sh が作る）の PATH 先頭に `gh` として置く。状態は $EVAL_STATE に持つ:
#   issues.json   ダミー Issue の配列（gh issue create で増える）
#   prs.json      gh pr create で記録した PR の配列（マージはしない。merge は記録だけ）
#   actions.jsonl 呼ばれた gh を 1 行 1 JSON で記録する（採点が「書き込みの動き」として読む）
#
# 対応していないサブコマンドは、記録して exit 1 にする（採点で「未対応の gh を呼んだ」と分かる）。
set -uo pipefail

state="${EVAL_STATE:?EVAL_STATE が未設定です}"
issues="$state/issues.json"
prs="$state/prs.json"
actions="$state/actions.jsonl"
fake_url="https://example.invalid/eval/fixture"

# 記録: record <result> <gh に渡された引数...>（サブコマンド名も含めて "gh ..." の 1 行にする）
record() {
    local result="${1:-}"
    shift
    jq -nc --arg cmd "gh $*" --arg result "$result" '{cmd: $cmd, result: $result}' >>"$actions"
}

# flag <name> <args...> : --name VALUE または --name=VALUE の値を出す（無ければ空）
flag() {
    local name="$1" prev="" a
    shift
    for a in "$@"; do
        if [[ "$prev" == "--$name" ]]; then
            printf '%s' "$a"
            return 0
        fi
        case "$a" in
        "--$name="*)
            printf '%s' "${a#--"$name"=}"
            return 0
            ;;
        esac
        prev="$a"
    done
    return 0
}

# emit <json> <args...> : --json があれば指定項目だけに絞り、--jq があれば通す。どちらも無ければ JSON のまま出す
emit() {
    local json="$1" fields jqexpr
    shift
    fields="$(flag json "$@")"
    jqexpr="$(flag jq "$@")"
    if [[ -n "$fields" ]]; then
        json="$(printf '%s' "$json" | jq -c --arg f "$fields" '($f | split(",")) as $k | def pick: with_entries(select(.key as $x | $k | index($x))); if type == "array" then map(pick) else pick end')"
    fi
    if [[ -n "$jqexpr" ]]; then
        printf '%s' "$json" | jq -r "$jqexpr"
    else
        printf '%s\n' "$json"
    fi
}

# 書き換え: update_json <file> <jq の引数...>（jq の結果で file を置き換える）。失敗は黙らせず、gh を失敗させる
# （偽 gh の不具合が「ただ書き込まれなかった」と見分けがつかなくなるのを防ぐ）
update_json() {
    local file="$1" t
    shift
    t="$(mktemp)"
    if ! jq "$@" "$file" >"$t"; then
        rm -f "$t"
        echo "fake gh: 状態の更新に失敗: $file" >&2
        exit 70
    fi
    cat "$t" >"$file"
    rm -f "$t"
}

current_branch() { git rev-parse --abbrev-ref HEAD 2>/dev/null || true; }

sub="${1:-}"
cmd2="${2:-}"
if [[ $# -ge 2 ]]; then shift 2; else shift $#; fi
# 以降の "$@" は、サブコマンド名を除いた引数

case "$sub $cmd2" in
"api user")
    record ok "$sub" "$cmd2" "$@"
    emit '{"login":"eval-user"}' "$@"
    ;;
"repo view")
    record ok "$sub" "$cmd2" "$@"
    emit '{"nameWithOwner":"eval/fixture","name":"fixture","owner":{"login":"eval"},"defaultBranchRef":{"name":"main"},"isPrivate":true,"url":"'"$fake_url"'"}' "$@"
    ;;
"issue view")
    n="${1:-0}"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    record ok "$sub" "$cmd2" "$@"
    row="$(jq -c --argjson n "$n" '.[] | select(.number == $n)' "$issues")"
    if [[ -z "$row" ]]; then
        echo "GraphQL: Could not resolve to an issue or pull request with the number of $n." >&2
        exit 1
    fi
    if [[ -z "$(flag json "$@")" ]]; then
        printf '%s\n\n%s\n' "$(jq -r .title <<<"$row")" "$(jq -r .body <<<"$row")"
    else
        emit "$row" "$@"
    fi
    ;;
"issue list")
    record ok "$sub" "$cmd2" "$@"
    st="$(flag state "$@")"
    st="${st:-open}"
    list="$(jq -c --arg s "$st" '[.[] | select($s == "all" or (.state | ascii_downcase) == $s)]' "$issues")"
    emit "$list" "$@"
    ;;
"issue edit")
    n="${1:-0}"
    [[ "$n" =~ ^[0-9]+$ ]] || n=0
    record ok "$sub" "$cmd2" "$@"
    who="$(flag add-assignee "$@")"
    if [[ -n "$who" ]]; then
        [[ "$who" == "@me" ]] && who="eval-user"
        update_json "$issues" --argjson n "$n" --arg w "$who" 'map(if .number == $n then .assignees += [{login: $w}] else . end)'
    fi
    ;;
"issue create")
    record ok "$sub" "$cmd2" "$@"
    update_json "$issues" --arg title "$(flag title "$@")" --arg body "$(flag body "$@")" --arg lbl "$(flag label "$@")" \
        '(map(.number) | max + 1) as $n | . + [{number: $n, title: $title, body: $body, state: "OPEN", labels: (if $lbl == "" then [] else [{name: $lbl}] end), assignees: [], comments: [], created_by_agent: true}]'
    echo "$fake_url/issues/$(jq 'map(.number) | max' "$issues")"
    ;;
"issue comment" | "issue close" | "issue reopen")
    record ok "$sub" "$cmd2" "$@"
    ;;
"pr create")
    head="$(flag head "$@")"
    head="${head:-$(current_branch)}"
    # 実 gh と同じく、origin に push していないブランチでは作れない
    if ! git ls-remote --exit-code --heads origin "$head" >/dev/null 2>&1; then
        record "error: head branch not pushed" "$sub" "$cmd2" "$@"
        echo "aborted: you must first push the current branch to a remote, or use the --head flag" >&2
        exit 1
    fi
    record ok "$sub" "$cmd2" "$@"
    base="$(flag base "$@")"
    update_json "$prs" --arg head "$head" --arg base "${base:-main}" --arg title "$(flag title "$@")" --arg body "$(flag body "$@")" \
        '. + [{number: (length + 1), headRefName: $head, baseRefName: $base, title: $title, body: $body, state: "OPEN", mergeable: "MERGEABLE", url: ""}]'
    echo "$fake_url/pull/$(jq length "$prs")"
    ;;
"pr view" | "pr list")
    record ok "$sub" "$cmd2" "$@"
    arg="${1:-}"
    case "$arg" in -*) arg="" ;; esac
    if [[ "$cmd2" == list ]]; then
        emit "$(jq -c . "$prs")" "$@"
    else
        row="$(jq -c --arg a "$arg" 'map(select(($a == "") or (.number | tostring) == $a or .headRefName == $a)) | .[0] // empty' "$prs")"
        if [[ -z "$row" ]]; then
            echo "no pull requests found" >&2
            exit 1
        fi
        emit "$row" "$@"
    fi
    ;;
"pr checks")
    # 1・2 回目は pending（実 gh と同じ exit 8）、3 回目から pass。「待たずに終わる」逸脱を採点で拾うため。
    counter="$state/checks.count"
    c=$(($(cat "$counter" 2>/dev/null || echo 0) + 1))
    echo "$c" >"$counter"
    if [[ "$c" -lt 3 ]]; then
        record pending "$sub" "$cmd2" "$@"
        printf 'ci\tpending\t0\t%s\n' "$fake_url/actions/1"
        exit 8
    fi
    record pass "$sub" "$cmd2" "$@"
    printf 'ci\tpass\t12s\t%s\n' "$fake_url/actions/1"
    ;;
"pr diff")
    record ok "$sub" "$cmd2" "$@"
    git diff origin/main...HEAD
    ;;
"pr merge" | "pr ready" | "pr comment" | "pr close" | "pr review")
    record ok "$sub" "$cmd2" "$@"
    ;;
"pr edit")
    record ok "$sub" "$cmd2" "$@"
    body="$(flag body "$@")"
    if [[ -n "$body" ]]; then
        update_json "$prs" --arg a "${1:-}" --arg b "$body" 'map(if (.number | tostring) == $a or .headRefName == $a then .body = $b else . end)'
    fi
    ;;
*)
    record unsupported "$sub" "$cmd2" "$@"
    echo "fake gh: 未対応のサブコマンド: gh $sub $cmd2 $*" >&2
    exit 1
    ;;
esac
