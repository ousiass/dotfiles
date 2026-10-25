#!/usr/bin/env bash
# 試験用 repo に、タスクセットに必要なコードとダミーの Issue を入れる。本物の repo は使わない。
#
#   evals/sandbox/seed.sh [--repo OWNER/NAME] [--url URL] [--no-issues] [--plan]
#
#   --repo       試験用 repo（既定 ousiass/dotfiles-eval-sandbox）。URL は https://github.com/<repo>.git
#   --url        push 先を URL で直接指定する（ローカルの bare repo で配線を確かめるとき用。--no-issues と併用）
#   --no-issues  Issue を作らない
#   --plan       何も push せず、入れるブランチと Issue の一覧を出す（ネットワークに出ない）
#
# 認証は、この環境の GH_TOKEN（evals/sandbox/README.md の fine-grained トークン）か gh のログインに任せる。
# 既存の gh のログインでは実行しない約束なので、`<root>/with-env` の中で実行すること（GH_TOKEN だけが効く）。
#
# 入れるもの（push は fast-forward のみ。force push も既存の ref の上書きもしない。在る ref・Issue は飛ばす）:
#   main                       題材（小さな bash ライブラリ。lib/fixture.sh の fixture_seed_files と同じ）
#   eval/<scenario>/main       シナリオの初期状態を main に重ねたもの（setup.sh が main に積んだ変更）
#   eval/<scenario>/<branch>   setup.sh が作った別ブランチ（refine 系の feat/wip など）
#   Issue                      tasks.jsonl の issues。ラベル eval と task:<id>。番号は --map で出す対応表に書く
# どのブランチも同じ初期コミットから伸びるので、PR・差分（main...branch）が成り立つ。
set -uo pipefail

EVALS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
export EVALS_DIR
# shellcheck source=../lib/fixture.sh
. "$EVALS_DIR/lib/fixture.sh"

repo=ousiass/dotfiles-eval-sandbox
url=""
issues=1
plan=0
while [[ $# -gt 0 ]]; do
    case "$1" in
    --repo | --url)
        [[ $# -ge 2 ]] || {
            echo "seed.sh: $1 に値が必要です" >&2
            exit 2
        }
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
        sed -n '2,22p' "${BASH_SOURCE[0]}"
        exit 0
        ;;
    *)
        echo "seed.sh: 不明な引数: $1" >&2
        exit 2
        ;;
    esac
done
[[ -n "$url" ]] || url="https://github.com/${repo}.git"
command -v jq >/dev/null || {
    echo "seed.sh: jq が必要です" >&2
    exit 2
}

tasks="$EVALS_DIR/tasks.jsonl"
scenarios="$(jq -r '.scenario // empty' "$tasks" | sort -u)"

# --- 計画 -----------------------------------------------------------------------------
tmp="$(mktemp -d "${TMPDIR:-/tmp}/eval-seed.XXXXXX")"
trap 'rm -rf "$tmp"' EXIT
origin="$tmp/origin.git"
git init -q --bare "$origin"
git -C "$origin" symbolic-ref HEAD refs/heads/main
git clone -q "$origin" "$tmp/seed" 2>/dev/null
(
    cd "$tmp/seed" || exit 1
    git config user.name eval
    git config user.email eval@example.invalid
    git checkout -q -b main
    fixture_seed_files
    git add -A
    git commit -q -m "chore: 初期コミット"
    git push -q -u origin main 2>/dev/null
) || {
    echo "seed.sh: 題材を作れない" >&2
    exit 1
}

# シナリオごとに、同じ初期コミットの上で setup.sh を実行し、増えたブランチを集める
refs=""
for s in $scenarios; do
    git clone -q "$origin" "$tmp/w-$s" 2>/dev/null || exit 1
    (
        cd "$tmp/w-$s" || exit 1
        git config user.name eval
        git config user.email eval@example.invalid
        printf '.sweep/\n' >>.git/info/exclude
        fixture_apply_scenario "$s"
    ) || {
        echo "seed.sh: シナリオ ${s} の初期状態を作れない" >&2
        exit 1
    }
    # push 先（tmp の origin）で、main 以外のブランチと、main がシナリオで進んだか
    while read -r b sha; do
        [[ -n "$b" ]] || continue
        case "$b" in
        main) [[ "$sha" == "$(git -C "$origin" rev-parse refs/heads/main)" ]] || true ;;
        esac
    done < <(git -C "$origin" for-each-ref --format='%(refname:short) %(objectname)' refs/heads)
    # fixture_apply_scenario は `git push origin HEAD` で、現在のブランチを origin に出す。
    # main に積んだシナリオは origin の main が進むので、seed の main に戻して、別名で取り直す
    sc_main="$(git -C "$origin" rev-parse refs/heads/main)"
    seed_main="$(git -C "$tmp/seed" rev-parse HEAD)"
    if [[ "$sc_main" != "$seed_main" ]]; then
        git -C "$origin" update-ref "refs/eval/$s/main" "$sc_main"
        git -C "$origin" update-ref refs/heads/main "$seed_main"
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

if [[ "$plan" -eq 1 ]]; then
    echo "push 先: ${url}"
    echo "main                      （題材）"
    for r in $refs; do echo "${r#*:refs/heads/}"; done
    echo "Issue: $(printf '%s\n' "$issues_plan" | grep -c .) 件"
    printf '%s\n' "$issues_plan" | jq -r '"  task:\(.task) #\(.local) \(.title)"'
    exit 0
fi

# --- push（在る ref は飛ばす。force しない） ------------------------------------------------
gitc() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }
remote_has() { gitc ls-remote --exit-code --heads "$url" "$1" >/dev/null 2>&1; }

if remote_has main; then
    echo "seed.sh: main は在るので飛ばす"
else
    gitc -C "$origin" push -q "$url" refs/heads/main:refs/heads/main || {
        echo "seed.sh: main を push できない（repo が無い・トークンに Contents 書き込みが無い、など）" >&2
        exit 1
    }
    echo "seed.sh: main を push した"
fi
for r in $refs; do
    dst="${r#*:refs/heads/}"
    if remote_has "$dst"; then
        echo "seed.sh: ${dst} は在るので飛ばす"
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
    echo "seed.sh: --no-issues なので Issue は作らない"
    exit 0
fi
command -v gh >/dev/null || {
    echo "seed.sh: gh が必要です（Issue を作る）" >&2
    exit 2
}
for l in eval spinoff; do gh label create "$l" --repo "$repo" --force >/dev/null 2>&1 || true; done
map="[]"
while IFS= read -r row; do
    [[ -n "$row" ]] || continue
    task="$(jq -r .task <<<"$row")"
    local_n="$(jq -r .local <<<"$row")"
    gh label create "task:${task}" --repo "$repo" --force >/dev/null 2>&1 || true
    existing="$(gh issue list --repo "$repo" --state all --label "task:${task}" --json number,title --jq "map(select(.title == $(jq -c .title <<<"$row"))) | .[0].number // empty" 2>/dev/null)"
    if [[ -n "$existing" ]]; then
        n="$existing"
        echo "seed.sh: task:${task} #${local_n} は在る（#${n}）ので飛ばす"
    else
        out="$(gh issue create --repo "$repo" --title "$(jq -r .title <<<"$row")" --body "$(jq -r .body <<<"$row")" --label eval --label "task:${task}")" || {
            echo "seed.sh: Issue を作れない（トークンに Issues 書き込みが無い、など）" >&2
            exit 1
        }
        n="${out##*/}"
        echo "seed.sh: task:${task} #${local_n} -> #${n}"
    fi
    map="$(jq -c --arg t "$task" --argjson l "$local_n" --argjson n "$n" '. + [{task: $t, local: $l, number: $n}]' <<<"$map")"
done <<<"$issues_plan"
echo "$map" | jq .
