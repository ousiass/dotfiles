#!/usr/bin/env bash
# 試験用 repo に、タスクセットに必要なコード・CI・ダミーの Issue を入れる。本物の repo は使わない。
#
#   evals/sandbox/seed.sh [--plan] [--no-issues] [--repo ousiass/dotfiles-eval-sandbox] [--url URL]
#
#   --plan       何も push せず、入れるものの一覧だけを出す（オフライン。リモートの有無は見ない）
#   --no-issues  Issue を作らない
#   --repo       固定の ousiass/dotfiles-eval-sandbox 以外は止まる
#   --url        push 先。既定は固定 repo の URL。固定 repo の URL か、実在するローカルの bare repo だけ許す
#                （ローカルのパスは、配線の確認とテスト用。ネットワークに出ず、Issue も作らない）
#
# 認証は、この環境の GH_TOKEN（evals/sandbox/README.md の fine-grained トークン）に任せる。`<root>/with-env` の中で実行すること。
# 既存の `gh` のログインでは実行しない約束なので、トークンが無いときは push で失敗する。
#
# このスクリプトは、固定 repo へ書き込める 2 つの経路のひとつ（もうひとつは reset.sh --apply）。run.sh は書き込まない。
# push は fast-forward のみ。force push も、既存の ref の上書きもしない。在る ref・Issue は飛ばす。
#
# 入れるもの:
#   main                       題材（小さな bash ライブラリ）と CI（.github/workflows/ci.yml。test.sh を回すだけ）。
#                              「初期状態」のコミットには `Eval-Seed: baseline` を入れる。reset.sh は main をこの中身へ戻す
#                              （main が既に在って目印が無ければ、先端の上に CI と目印のコミットを 1 本積む。通常の push）
#   eval/<scenario>/main       シナリオの初期状態（setup.sh）を、初期状態のコミットに重ねたもの
#   eval/<scenario>/<branch>   setup.sh が作った別ブランチ（refine 系の feat/wip など）
#   Issue                      tasks.jsonl の issues。ラベル eval と task:<id>。番号は evals/sandbox/issue-map.json と一致させる
# どのブランチも同じ初期状態のコミットから伸びるので、PR・差分が成り立つ。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export EVALS_DIR
# shellcheck source=../lib/fixture.sh
. "$EVALS_DIR/lib/fixture.sh"
# shellcheck source=lib.sh
. "$EVALS_DIR/sandbox/lib.sh"

repo="$SANDBOX_REPO"
url=""
issues=1
plan=0
while [[ $# -gt 0 ]]; do
    case "$1" in
    --repo | --url)
        [[ $# -ge 2 ]] || sandbox_fail "$1 に値が必要です"
        case "$1" in --repo) repo="$2" ;; --url) url="$2" ;; esac
        shift 2
        ;;
    --no-issues)
        issues=0
        shift
        ;;
    --plan)
        plan=1
        shift
        ;;
    -h | --help)
        sed -n '2,26p' "${BASH_SOURCE[0]}"
        exit 0
        ;;
    *) sandbox_fail "不明な引数: $1" ;;
    esac
done
sandbox_require_repo "$repo"
[[ -n "$url" ]] || url="$SANDBOX_URL"
sandbox_require_url "$url"
command -v jq >/dev/null || sandbox_fail "jq が必要です"
if sandbox_is_local_url "$url" && [[ "$issues" -eq 1 ]]; then
    echo "seed.sh: ローカルの push 先なので Issue は作らない"
    issues=0
fi

tasks="$EVALS_DIR/tasks.jsonl"
scenarios="$(jq -r '.scenario // empty' "$tasks" | sort -u)"
gitc() { sandbox_git "$@"; }
remote_has() { gitc ls-remote --exit-code --heads "$url" "$1" >/dev/null 2>&1; }

tmp="$(mktemp -d "${TMPDIR:-/tmp}/eval-seed.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT

# --- 初期状態（main）------------------------------------------------------------------------
# 作業用の repo。リモートに main が在れば、その先端から始める（履歴を作り直さない）
work="$tmp/seed"
git init -q "$work"
git -C "$work" config user.name eval
git -C "$work" config user.email eval@example.invalid
new_main=0
remote_main=0
if [[ "$plan" -eq 0 ]] && remote_has main; then
    remote_main=1
    gitc -C "$work" fetch -q "$url" refs/heads/main:refs/heads/remote-main || sandbox_fail "main を fetch できない"
    git -C "$work" checkout -q -b main remote-main
else
    git -C "$work" checkout -q -b main
fi
baseline="$(sandbox_baseline "$work" main)"
if [[ -z "$baseline" ]]; then
    new_main=1
    (
        cd "$work" || exit 1
        if [[ "$remote_main" -eq 0 ]]; then
            fixture_seed_files
            msg="chore: 初期コミット"
        else
            msg="ci: 試験用 repo の CI と初期状態の目印を追加"
        fi
        mkdir -p .github/workflows
        [[ -f .github/workflows/ci.yml ]] || sandbox_ci_workflow >.github/workflows/ci.yml
        git add -A
        git commit -q --allow-empty -m "${msg}

${SANDBOX_BASELINE_TRAILER}"
    ) || sandbox_fail "初期状態のコミットを作れない"
    baseline="$(git -C "$work" rev-parse HEAD)"
fi

# シナリオを作るための手元の origin（ネットワークに出ない）。main は初期状態のコミットに置く
origin="$tmp/origin.git"
git init -q --bare "$origin"
git -C "$origin" symbolic-ref HEAD refs/heads/main
git -C "$work" push -q "$origin" "${baseline}:refs/heads/main" || sandbox_fail "手元の origin を作れない"

# シナリオごとに、同じ初期状態の上で setup.sh を実行し、増えたブランチを集める
refs=""
for s in $scenarios; do
    git clone -q "$origin" "$tmp/w-$s" 2>/dev/null || sandbox_fail "clone できない"
    (
        cd "$tmp/w-$s" || exit 1
        git config user.name eval
        git config user.email eval@example.invalid
        printf '.sweep/\n' >>.git/info/exclude
        fixture_apply_scenario "$s"
    ) || sandbox_fail "シナリオ ${s} の初期状態を作れない"
    # fixture_apply_scenario は現在のブランチを origin へ push する。main に積んだシナリオは origin の main が進むので、
    # 別名の ref に退避して main を初期状態に戻す（手元の origin だけの操作）
    sc_main="$(git -C "$origin" rev-parse refs/heads/main)"
    if [[ "$sc_main" != "$baseline" ]]; then
        git -C "$origin" update-ref "refs/eval/$s/main" "$sc_main"
        git -C "$origin" update-ref refs/heads/main "$baseline"
        refs="$refs refs/eval/$s/main:refs/heads/eval/$s/main"
    fi
    while read -r b; do
        [[ -n "$b" && "$b" != main ]] || continue
        git -C "$origin" update-ref "refs/eval/$s/$b" "refs/heads/$b"
        git -C "$origin" update-ref -d "refs/heads/$b"
        refs="$refs refs/eval/$s/$b:refs/heads/eval/$s/$b"
    done < <(git -C "$origin" for-each-ref --format='%(refname:short)' refs/heads)
done

issues_plan="$(jq -c '. as $t | (.issues // []) | to_entries[] | {task: $t.id, local: (.key + 1), title: .value.title, body: .value.body}' "$tasks")"

SEED_LABELS=(eval spinoff bug type:bug type:feat type:chore type:refactor type:docs severity:critical severity:high severity:medium severity:low priority:high priority:medium priority:low area:app)
if [[ "$plan" -eq 1 ]]; then
    echo "push 先: ${url}（固定 repo: ${SANDBOX_REPO}）"
    echo "main                      （題材と CI。初期状態のコミットを作る。既に在る main には、先端の上に CI と目印を積む）"
    for r in $refs; do echo "${r#*:refs/heads/}"; done
    echo "Issue: $(printf '%s\n' "$issues_plan" | grep -c .) 件"
    printf '%s\n' "$issues_plan" | jq -r '"  task:\(.task) #\(.local) \(.title)"'
    echo "ラベル: ${SEED_LABELS[*]}"
    exit 0
fi

# --- push（在る ref は飛ばす。force しない） ------------------------------------------------
if [[ "$new_main" -eq 1 ]]; then
    gitc -C "$work" push -q "$url" "${baseline}:refs/heads/main" || {
        echo "seed.sh: main を push できない（トークンの権限・main の更新、など）" >&2
        exit 1
    }
    echo "seed.sh: main に初期状態のコミットを push した（${baseline:0:7}）"
else
    echo "seed.sh: main に初期状態のコミットが在る（${baseline:0:7}）ので飛ばす"
fi
for r in $refs; do
    dst="${r#*:refs/heads/}"
    if remote_has "$dst"; then
        # 初期状態のコミットから伸びていない（CI を足す前に作った古いもの）ref は、reset.sh --apply のあと seed.sh を再実行して作り直す
        if gitc -C "$work" fetch -q "$url" "refs/heads/${dst}:refs/eval-remote/${dst}" 2>/dev/null &&
            ! git -C "$work" merge-base --is-ancestor "$baseline" "refs/eval-remote/${dst}" 2>/dev/null; then
            echo "seed.sh: 警告: ${dst} は在るが、初期状態のコミットから伸びていない（古い）。reset.sh --apply のあと seed.sh を再実行する"
        else
            echo "seed.sh: ${dst} は在るので飛ばす"
        fi
    else
        gitc -C "$origin" push -q "$url" "${r%%:*}:refs/heads/${dst}" || {
            echo "seed.sh: ${dst} を push できない" >&2
            exit 1
        }
        echo "seed.sh: ${dst} を push した"
    fi
done

# --- Issue -----------------------------------------------------------------------------
if [[ "$issues" -eq 0 ]]; then
    echo "seed.sh: Issue は作らない"
    exit 0
fi
command -v gh >/dev/null || sandbox_fail "gh が必要です（Issue を作る）"
# gh の呼び出し（ラベル・Issue。操作の対象は --repo の固定の repo だけ）。専用トークンに Issues / Labels の書き込みが無いときは、
# EVAL_GH_USER_CONFIG_DIR（普段の gh のログインの設定ディレクトリ）を付けると、この呼び出しだけがそちらで動く（git の push には使わない。reset.sh と同じ約束）
sgh() {
    if [[ -n "${EVAL_GH_USER_CONFIG_DIR:-}" ]]; then
        [[ -r "$EVAL_GH_USER_CONFIG_DIR/hosts.yml" ]] || sandbox_fail "EVAL_GH_USER_CONFIG_DIR（${EVAL_GH_USER_CONFIG_DIR}）に hosts.yml が無い"
        env -u GH_TOKEN -u GITHUB_TOKEN -u GH_ENTERPRISE_TOKEN -u GITHUB_ENTERPRISE_TOKEN GH_CONFIG_DIR="$EVAL_GH_USER_CONFIG_DIR" gh "$@"
    else
        gh "$@"
    fi
}
# ラベル: eval・spinoff に加えて、spinoff-issue が付けるラベル（type:* / severity:* / priority:* / bug / area:app）。
# spinoff-issue は「spinoff 以外の不足ラベルは作らず、ユーザーの承認を取る」決まりで、非対話の claude -p では承認が取れず、
# 起票で止まる実行が出る（Phase 2 の baseline3 の impl-spinoff r1）。題材のモジュール（app.sh）の area:app も入れる
for l in "${SEED_LABELS[@]}"; do sgh label create "$l" --repo "$repo" --force >/dev/null 2>&1 || true; done
map="[]"
while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    task="$(jq -r .task <<<"$row")"
    local_n="$(jq -r .local <<<"$row")"
    sgh label create "task:${task}" --repo "$repo" --force >/dev/null 2>&1 || true
    existing="$(sgh issue list --repo "$repo" --state all --label "task:${task}" --json number,title --jq "map(select(.title == $(jq -c .title <<<"$row"))) | .[0].number // empty" 2>/dev/null)"
    if [[ -n "$existing" ]]; then
        n="$existing"
        echo "seed.sh: task:${task} #${local_n} は在る（#${n}）ので飛ばす"
    else
        out="$(sgh issue create --repo "$repo" --title "$(jq -r .title <<<"$row")" --body "$(jq -r .body <<<"$row")" --label eval --label "task:${task}")" || {
            echo "seed.sh: Issue を作れない（トークンに Issues 書き込みが無い、など）" >&2
            exit 1
        }
        n="${out##*/}"
        echo "seed.sh: task:${task} #${local_n} -> #${n}"
    fi
    map="$(jq -c --arg t "$task" --argjson l "$local_n" --argjson n "$n" '. + [{task: $t, local: $l, number: $n}]' <<<"$map")"
done <<<"$issues_plan"

# 番号の対応表は、run.sh --remote がプロンプトの Issue 番号を置き換えるのに使う。コミット済みの表と食い違ったら止める
mapfile_path="$EVALS_DIR/sandbox/issue-map.json"
if [[ -f "$mapfile_path" ]]; then
    if [[ "$(jq -c 'sort_by(.number)' "$mapfile_path")" != "$(jq -c 'sort_by(.number)' <<<"$map")" ]]; then
        echo "seed.sh: Issue の番号が evals/sandbox/issue-map.json と食い違う。表を直すか、試験用 repo を確認する" >&2
        jq . <<<"$map"
        exit 1
    fi
    echo "seed.sh: Issue の番号は issue-map.json と一致する"
else
    jq . <<<"$map" >"$mapfile_path"
    echo "seed.sh: ${mapfile_path} を書いた（コミットする）"
fi
