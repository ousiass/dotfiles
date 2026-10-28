#!/usr/bin/env bash
# 試験用 repo（ousiass/dotfiles-eval-sandbox）を初期状態に戻す。人が実行する。run.sh の前後で自動には走らせない。
#
#   evals/sandbox/reset.sh [--plan]            何を閉じる・消す・戻すかの一覧を出すだけ（既定。何も変えない）
#   evals/sandbox/reset.sh --apply [--max N]   一覧のとおりに実行する。N は 50 以下（既定 50）
#   evals/sandbox/reset.sh ... [--repo ousiass/dotfiles-eval-sandbox] [--url URL]
#
# 安全策:
#   - 対象は ousiass/dotfiles-eval-sandbox だけ。--repo に別の repo を渡すと止まる。--url も、この repo の URL か、
#     実在するローカルの bare repo（テスト用。ネットワークに出ない）だけ許す
#   - 動かすのは次のものだけ。main・初期状態のコミット・それ以外のブランチ・eval ラベルの無い PR / Issue には触れない
#       1. eval/ で始まるブランチの削除（seed.sh が作ったシナリオ用ブランチ eval/<scenario>/... も含む。あとで seed.sh が作り直す）
#       2. eval ラベルの付いた、開いている PR を閉じる（マージ済みの PR は戻せないので、一覧に出すだけ）
#       3. eval ラベルの付いた Issue: タスクの Issue（issue-map.json の番号）が閉じていれば開き直し、タイトルと本文を
#          tasks.jsonl のとおりに戻し、アサインを外す。エージェントが作った Issue（issue-map.json に無い番号）は閉じる
#          （Issue は GitHub の API では消せないので、閉じる。コメントは残る）
#       4. main の戻し: 中身が初期状態のコミットと違うときだけ、main の先端の上に「初期状態と同じ中身にするコミット」を
#          1 本積んで、通常の push で戻す。force push はしない（保護ルールがあれば失敗して止まる）
#   - 1 回で動かす件数（上の 1〜4 の合計）が上限（50）を超えたら、何もせず止まる
#   - GitHub に対しては GH_TOKEN だけで動く（試験用 repo だけに書ける fine-grained トークン）。`<root>/with-env` の中で実行すること。
#     既存の gh のログインでは、EVAL_GH_USER_CONFIG_DIR を付けたときだけ動く（付けなければ GH_TOKEN と EVAL_SANDBOX_ROOT が無いと止まる）
#   - 消したあとの seed.sh の再実行は人が行う（シナリオ用ブランチを作り直す）
#
# 環境変数 RESET_GH: gh の代わりに呼ぶコマンド（テスト用。repo は固定のまま渡る）。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=lib.sh
. "$EVALS_DIR/sandbox/lib.sh"

REPO="$SANDBOX_REPO"
url=""
apply=0
plan_flag=0
max=50
while [[ $# -gt 0 ]]; do
    case "$1" in
    --apply)
        apply=1
        shift
        ;;
    --plan)
        plan_flag=1
        shift
        ;;
    --repo | --url | --max)
        [[ $# -ge 2 ]] || sandbox_fail "$1 に値が必要です"
        case "$1" in --repo) REPO="$2" ;; --url) url="$2" ;; --max) max="$2" ;; esac
        shift 2
        ;;
    -h | --help)
        sed -n '2,27p' "${BASH_SOURCE[0]}"
        exit 0
        ;;
    *) sandbox_fail "不明な引数: $1" ;;
    esac
done
sandbox_require_repo "$REPO"
[[ "$apply" -eq 0 || "$plan_flag" -eq 0 ]] || sandbox_fail "--plan と --apply は一緒に使えません"
[[ "$max" =~ ^[0-9]+$ && "$max" -ge 1 && "$max" -le 50 ]] || sandbox_fail "--max は 1〜50 の整数です"
[[ -n "$url" ]] || url="$SANDBOX_URL"
sandbox_require_url "$url"
command -v jq >/dev/null || sandbox_fail "jq が必要です"

local_url=0
sandbox_is_local_url "$url" && local_url=1
GH="${RESET_GH:-gh}"
use_gh=1
if [[ "$local_url" -eq 1 ]]; then
    # テスト用。gh は RESET_GH が指定されたときだけ使う（本物の gh は呼ばない）
    [[ -n "${RESET_GH:-}" ]] || use_gh=0
else
    if [[ -n "${EVAL_GH_USER_CONFIG_DIR:-}" ]]; then
        # 普段の gh のログインを使う（専用トークンの権限が足りないとき）。トークンは環境変数にもファイルにも出さない。操作の対象は固定の repo だけ
        [[ -r "$EVAL_GH_USER_CONFIG_DIR/hosts.yml" ]] || sandbox_fail "EVAL_GH_USER_CONFIG_DIR（${EVAL_GH_USER_CONFIG_DIR}）に hosts.yml が無い"
        export GH_CONFIG_DIR="$EVAL_GH_USER_CONFIG_DIR"
        unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
    else
        [[ -n "${GH_TOKEN:-}" ]] || sandbox_fail "GH_TOKEN が必要です（試験用 repo だけに書ける fine-grained トークン。EVAL_GH_USER_CONFIG_DIR で普段の gh のログインも使える）。evals/sandbox/README.md"
    fi
    [[ -n "${EVAL_SANDBOX_ROOT:-}" ]] || sandbox_fail "<root>/with-env の中で実行してください（EVAL_SANDBOX_ROOT が無い）"
    command -v gh >/dev/null || sandbox_fail "gh が必要です"
fi

tmp="$(mktemp -d "${TMPDIR:-/tmp}/eval-reset.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
ops="$tmp/ops.tsv" # kind <TAB> target <TAB> note
: >"$ops"
op() { printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >>"$ops"; }

# --- 調べる（読み取りだけ） -----------------------------------------------------------------
clone="$tmp/clone"
sandbox_git clone -q --no-checkout "$url" "$clone" 2>/dev/null || sandbox_fail "試験用 repo を clone できない（トークン・ネットワーク）"
git -C "$clone" config user.name eval
git -C "$clone" config user.email eval@example.invalid

# 1. eval/ で始まるブランチ（main と、eval/ で始まらないものには触れない）
while read -r b; do
    [[ "$b" == eval/* ]] || continue
    op DELETE-BRANCH "$b"
done < <(git -C "$clone" for-each-ref --format='%(refname:short)' refs/remotes/origin | sed 's|^origin/||' | grep -v '^HEAD$')

# 4. main（先に基準を決める）
baseline="$(sandbox_baseline "$clone" origin/main)"
main_tip="$(git -C "$clone" rev-parse origin/main 2>/dev/null)"
[[ -n "$baseline" ]] || sandbox_fail "main に初期状態のコミットが無い（seed.sh を実行していない repo では戻せない）"
if [[ "$(git -C "$clone" rev-parse "origin/main^{tree}")" != "$(git -C "$clone" rev-parse "${baseline}^{tree}")" ]]; then
    op RESTORE-MAIN "${main_tip:0:7}" "初期状態（${baseline:0:7}）と同じ中身にするコミットを 1 本積む"
fi

issue_map="$EVALS_DIR/sandbox/issue-map.json"
tasks="$EVALS_DIR/tasks.jsonl"
merged_n=0 # マージ済みの PR は戻せないので、一覧には出さず件数だけ数える
if [[ "$use_gh" -eq 1 ]]; then
    # 2. eval ラベルの付いた PR
    prs="$("$GH" pr list --repo "$REPO" --label eval --state all --limit 500 --json number,headRefName,state 2>/dev/null)" || sandbox_fail "PR の一覧を読めない"
    while IFS=$'\t' read -r n head st; do
        [[ -n "$n" ]] || continue
        case "$st" in
        OPEN) op CLOSE-PR "#${n}" "$head" ;;
        MERGED) merged_n=$((merged_n + 1)) ;;
        esac
    done < <(jq -r '.[] | [.number, .headRefName, .state] | @tsv' <<<"$prs")

    # 3. eval ラベルの付いた Issue
    issues="$("$GH" issue list --repo "$REPO" --label eval --state all --limit 500 --json number,title,body,state,assignees 2>/dev/null)" || sandbox_fail "Issue の一覧を読めない"
    while IFS=$'\t' read -r n st nassign; do
        [[ -n "$n" ]] || continue
        entry="$(jq -c --argjson n "$n" '.[] | select(.number == $n)' "$issue_map")"
        if [[ -z "$entry" ]]; then
            [[ "$st" == OPEN ]] && op CLOSE-ISSUE "#${n}" "エージェントが作った Issue（issue-map.json に無い）"
            continue
        fi
        [[ "$st" != CLOSED ]] || op REOPEN-ISSUE "#${n}"
        [[ "$nassign" -eq 0 ]] || op UNASSIGN-ISSUE "#${n}" "アサイン ${nassign} 件"
        want="$(jq -c --argjson e "$entry" -s '.[] | select(.id == $e.task) | .issues[$e.local - 1] | {title, body}' "$tasks")"
        have="$(jq -c --argjson n "$n" '.[] | select(.number == $n) | {title, body}' <<<"$issues")"
        [[ "$want" == "$have" ]] || op RESTORE-ISSUE-TEXT "#${n}" "タイトルか本文が tasks.jsonl と違う"
    done < <(jq -r '.[] | [.number, .state, (.assignees | length)] | @tsv' <<<"$issues")
fi

# --- 一覧 -------------------------------------------------------------------------------------
total="$(grep -c . "$ops" || true)"
actionable="$total"
echo "対象 repo: ${REPO}（push 先: ${url}）"
if [[ "$total" -eq 0 ]]; then
    echo "戻すものはありません（初期状態です）"
else
    awk -F'\t' '{ printf "  %-20s %-40s %s\n", $1, $2, $3 }' "$ops"
fi
echo "動かす件数: ${actionable}（上限 ${max}）"
[[ "$merged_n" -eq 0 ]] || echo "マージ済みの eval の PR: ${merged_n} 件（戻せないので対象外。GitHub では PR を削除できない）"
[[ "$use_gh" -eq 1 ]] || echo "（ローカルの push 先で gh の指定が無いので、PR・Issue は調べていない）"

if [[ "$actionable" -gt "$max" ]]; then
    echo "reset.sh: 件数が上限（${max}）を超えている。何もしません。内容を確かめて、手で片付けるか --max を（50 まで）上げてください" >&2
    exit 1
fi
if [[ "$apply" -eq 0 ]]; then
    echo "（--plan。何も変えていません。実行するなら --apply を付けて、もう一度実行してください）"
    exit 0
fi
[[ "$actionable" -gt 0 ]] || exit 0

# --- 実行（PR → ブランチ → Issue → main の順） ---------------------------------------------------
fail=0
step() { # step <説明> <コマンド...>
    local what="$1"
    shift
    if "$@" >/dev/null 2>"$tmp/err"; then echo "  済: ${what}"; else
        echo "  失敗: ${what}: $(head -c 200 "$tmp/err" | tr '\n' ' ')" >&2
        fail=1
    fi
}
while IFS=$'\t' read -r kind target _; do
    [[ "$kind" == CLOSE-PR ]] || continue
    step "PR ${target} を閉じる" "$GH" pr close "${target#\#}" --repo "$REPO"
done <"$ops"
while IFS=$'\t' read -r kind target _; do
    [[ "$kind" == DELETE-BRANCH ]] || continue
    # 二重の確認: eval/ で始まらない名前・main は、ここまで来ても消さない
    case "$target" in eval/*) ;; *) continue ;; esac
    [[ "$target" != main ]] || continue
    step "ブランチ ${target} を消す" sandbox_git -C "$clone" push "$url" --delete "refs/heads/${target}"
done <"$ops"
while IFS=$'\t' read -r kind target _; do
    n="${target#\#}"
    case "$kind" in
    REOPEN-ISSUE) step "Issue ${target} を開き直す" "$GH" issue reopen "$n" --repo "$REPO" ;;
    UNASSIGN-ISSUE)
        who="$("$GH" issue view "$n" --repo "$REPO" --json assignees --jq '[.assignees[].login] | join(",")' 2>/dev/null)"
        [[ -z "$who" ]] || step "Issue ${target} のアサインを外す" "$GH" issue edit "$n" --repo "$REPO" --remove-assignee "$who"
        ;;
    RESTORE-ISSUE-TEXT)
        entry="$(jq -c --argjson n "$n" '.[] | select(.number == $n)' "$issue_map")"
        want="$(jq -c --argjson e "$entry" -s '.[] | select(.id == $e.task) | .issues[$e.local - 1]' "$tasks")"
        step "Issue ${target} のタイトルと本文を戻す" "$GH" issue edit "$n" --repo "$REPO" --title "$(jq -r .title <<<"$want")" --body "$(jq -r .body <<<"$want")"
        ;;
    CLOSE-ISSUE) step "Issue ${target} を閉じる" "$GH" issue close "$n" --repo "$REPO" ;;
    esac
done <"$ops"
if grep -q '^RESTORE-MAIN' "$ops"; then
    # force しない。main の先端の上に、初期状態と同じ中身（tree）のコミットを 1 本積む
    cur="$(sandbox_git -C "$clone" ls-remote "$url" refs/heads/main | awk '{print $1}')"
    if [[ "$cur" != "$main_tip" ]]; then
        echo "  失敗: main が調べたあとに動いた（${cur:0:7}）。もう一度 --plan から" >&2
        fail=1
    else
        restore="$(git -C "$clone" commit-tree "${baseline}^{tree}" -p "$main_tip" -m "chore: main を初期状態（${baseline:0:7}）の中身に戻す

Eval-Reset: restore main to the tree of ${baseline}")" || sandbox_fail "戻しのコミットを作れない"
        step "main を初期状態の中身に戻す（${restore:0:7}。通常の push）" sandbox_git -C "$clone" push "$url" "${restore}:refs/heads/main"
    fi
fi
[[ "$fail" -eq 0 ]] || {
    echo "reset.sh: 一部が失敗した。--plan で残りを確かめる" >&2
    exit 1
}
echo "完了。シナリオ用ブランチを作り直すなら、seed.sh を実行してください"
