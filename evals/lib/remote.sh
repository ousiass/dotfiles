# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154
# （mode・root・real_gh・r_* は run.sh と共有するグローバル。run.sh が読む r_* は run.sh 側で使う）
# run.sh --remote の部品（source して使う）。ローカルの使い捨て repo ではなく、試験用 repo（evals/sandbox/lib.sh の SANDBOX_REPO）に
# 実際に書き込ませるために、準備・初期状態の検査・実行後の取り出しをする。
#
# 書き込みの経路は、エージェントの git push と gh（記録用ラッパー lib/gh-record.sh 経由）だけ。run.sh 自身は試験用 repo に書き込まない
# （ブランチも PR も Issue も作らない・消さない。初期化は人が reset.sh --apply で行う）。
#
# dry では、試験用 repo の代わりにローカルの bare repo（seed.sh --url <ローカルのパス> で同じ内容を入れたもの）と、
# 偽の gh（lib/fake-gh.sh）を使う。ネットワークには出ず、本物の gh も呼ばない。
#
# 実行ごとに $sb/state/ へ置くもの（grade.sh が読む。ローカルの使い捨て repo と同じ形）:
#   base            PR のマージ先（シナリオに eval/<scenario>/main があればそれ、無ければ main）
#   work_branch     最初にチェックアウトしておくブランチ（refine 系は eval/<scenario>/feat/wip、ほかは base）
#   setup_heads     実行の直前のリモートの各ブランチ（「名前 sha」）
#   issue_map.json  タスクの中の Issue 番号（1 始まり）→ GitHub の番号
#   pre_max         実行の直前の Issue・PR の最大番号（これより大きい番号がこの実行で作られたもの）

EVALS_SANDBOX_DIR="$EVALS_DIR/sandbox"
# shellcheck source=../sandbox/lib.sh
. "$EVALS_SANDBOX_DIR/lib.sh"

# remote_init : run.sh の開始時に 1 回。dry は試験用 repo の代わりのローカル repo を作る。live は gh とトークンを確かめる
remote_init() {
    if [[ "$mode" == dry ]]; then
        remote_seed_dir="$root/remote-seed.git"
        git init -q --bare "$remote_seed_dir"
        git -C "$remote_seed_dir" symbolic-ref HEAD refs/heads/main
        bash "$EVALS_SANDBOX_DIR/seed.sh" --url "$remote_seed_dir" >"$root/seed.log" 2>&1 || {
            echo "run.sh: dry 用の試験用 repo を作れない（$root/seed.log）" >&2
            return 1
        }
    else
        real_gh="$(command -v gh)" || {
            echo "run.sh: --remote --live には gh が要ります" >&2
            return 1
        }
        if [[ -n "${EVAL_GH_USER_CONFIG_DIR:-}" ]]; then
            # 普段の gh のログインを使う。トークンは環境変数にもファイルにも出さない（gh が設定ディレクトリから読む）。
            # run.sh 自身の gh・git（クローン・取り出し）はこの設定ディレクトリで動かし、エージェントには GH_TOKEN を渡さない。
            # エージェントの gh は記録用ラッパー（lib/gh-record.sh）経由で、ラッパーだけが EVAL_GH_USER_CONFIG_DIR を使う
            [[ -r "$EVAL_GH_USER_CONFIG_DIR/hosts.yml" ]] || {
                echo "run.sh: EVAL_GH_USER_CONFIG_DIR（${EVAL_GH_USER_CONFIG_DIR}）に hosts.yml が無い" >&2
                return 1
            }
            r_isolated_gh_config="${GH_CONFIG_DIR:-}"
            export GH_CONFIG_DIR="$EVAL_GH_USER_CONFIG_DIR"
            unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
            echo "run.sh: 注意: 普段の gh のログイン（${EVAL_GH_USER_CONFIG_DIR}）を使う。書き込みは記録用ラッパーが固定の repo（${SANDBOX_REPO}）に絞る" >&2
        else
            [[ -n "${GH_TOKEN:-}" ]] || {
                echo "run.sh: --remote --live には GH_TOKEN（試験用 repo だけに書ける fine-grained トークン）が要ります。evals/sandbox/README.md を参照" >&2
                return 1
            }
        fi
    fi
}

# remote_gh <sb> <gh の引数...> : 記録しない読み取り用の gh（dry は偽 gh、live は本物。対象は固定の repo）
remote_gh() {
    local sb="$1"
    shift
    if [[ "$mode" == dry ]]; then
        (cd "$sb/repo" && EVAL_STATE="$sb/state" EVAL_FAKE_NO_RECORD=1 bash "$EVALS_DIR/lib/fake-gh.sh" "$@")
    else
        (cd "$sb/repo" && GH_REPO="$SANDBOX_REPO" "$real_gh" "$@")
    fi
}

# remote_heads <url> : 「名前 sha」を 1 行ずつ
remote_heads() {
    sandbox_git ls-remote --heads "$1" 2>/dev/null | awk '{ sub("^refs/heads/", "", $2); print $2, $1 }'
}

# remote_check_ref <repo> <scenario> <ref> : 初期状態のまま（初期状態のコミット、またはその上にシナリオの 1 コミット）か
remote_check_ref() {
    local dir="$1" scen="$2" ref="$3" baseline n subject
    baseline="$(sandbox_baseline "$dir" origin/main)"
    [[ -n "$baseline" ]] || {
        echo "origin/main に初期状態のコミットが無い（seed.sh が要る）" >&2
        return 1
    }
    git -C "$dir" merge-base --is-ancestor "$baseline" "origin/$ref" 2>/dev/null || {
        echo "${ref} が初期状態のコミットから伸びていない（古い。reset.sh --apply のあと seed.sh を再実行する）" >&2
        return 1
    }
    n="$(git -C "$dir" rev-list --count "$baseline..origin/$ref")"
    if [[ "$ref" == main ]]; then
        [[ "$(git -C "$dir" rev-parse "origin/main^{tree}")" == "$(git -C "$dir" rev-parse "${baseline}^{tree}")" ]] || {
            echo "main が初期状態の中身と違う（reset.sh --plan で確認する）" >&2
            return 1
        }
        return 0
    fi
    [[ "$n" -le 1 ]] || {
        echo "${ref} が初期状態から進んでいる（${n} コミット。reset.sh --apply のあと seed.sh を再実行する）" >&2
        return 1
    }
    if [[ "$n" -eq 1 ]]; then
        subject="$(git -C "$dir" log -1 --format=%s "origin/$ref")"
        [[ "$subject" == "chore: シナリオの初期状態 (${scen})" ]] || {
            echo "${ref} の先端がシナリオの初期状態のコミットではない（${subject}）" >&2
            return 1
        }
    fi
}

# remote_prompt <prompt> <base> <prefix> <map-json> [<作業ブランチ>] : タスクのプロンプトを試験用 repo 向けに直す
#   - #<n>（タスクの中の番号）を GitHub の Issue 番号に置き換える
#   - --base <ブランチ> の値を、このシナリオの base にする
#   - ベースブランチとブランチ名の約束を足す。作業ブランチ（refine 系の eval/<scenario>/feat/wip）がベースと違うときは、そこへ直接 push してよいと書く
#     （書かないと、プレフィックスの約束を守って新しいブランチを作り、「作業ブランチを直す」タスクが成り立たない）
remote_prompt() {
    local prompt="$1" base="$2" prefix="$3" map="$4" start="${5:-}" w out="" prev="" n g
    local -a words
    read -r -a words <<<"$prompt"
    for w in "${words[@]}"; do
        if [[ "$w" =~ ^#([0-9]+)$ ]]; then
            n="${BASH_REMATCH[1]}"
            g="$(jq -r --argjson i "$n" '.[$i - 1] // empty' <<<"$map")"
            w="#${g:-$n}"
        elif [[ "$prev" == --base ]]; then
            w="$base"
        fi
        out="${out:+$out }$w"
        prev="$w"
    done
    if [[ -n "$start" && "$start" != "$base" ]]; then
        printf '%s ベースブランチは %s（PR のマージ先もこれ）。いまチェックアウトしている作業ブランチ %s を直すときは、新しいブランチを作らず、そのブランチに push する。新しくブランチを作るときだけ、名前を %s で始める。' "$out" "$base" "$start" "$prefix"
    else
        printf '%s ベースブランチは %s（PR のマージ先もこれ）。作るブランチ名は %s で始める。' "$out" "$base" "$prefix"
    fi
}

# remote_prepare <sb> <taskfile> <run-seq> : 試験用 repo（dry はローカルの代わり）から作業用の clone を作り、state/ を用意する。
# 失敗（初期状態ではない・clone できない）は、理由を標準エラーに出して 1 を返す。run.sh は何も書き込まない
remote_prepare() {
    local sb="$1" taskfile="$2" seq="$3" id scen heads
    id="$(jq -r .id "$taskfile")"
    id="${id%%@*}" # --violate のときは「<id>@<逸脱>」になっている
    scen="$(jq -r '.scenario // ""' "$taskfile")"
    mkdir -p "$sb/bin" "$sb/state" "$sb/home"
    if [[ "$mode" == dry ]]; then
        cp -R "$remote_seed_dir" "$sb/remote.git" || return 1
        r_url="$sb/remote.git"
    else
        r_url="$SANDBOX_URL"
    fi
    sandbox_require_url "$r_url"

    heads="$(remote_heads "$r_url")"
    [[ -n "$heads" ]] || {
        echo "試験用 repo のブランチを読めない（トークン・ネットワーク）" >&2
        return 1
    }
    r_base=main
    r_start=main
    if [[ -n "$scen" ]]; then
        printf '%s\n' "$heads" | awk -v b="eval/$scen/main" '$1 == b { f = 1 } END { exit !f }' && r_base="eval/$scen/main"
        r_start="$r_base"
        printf '%s\n' "$heads" | awk -v b="eval/$scen/feat/wip" '$1 == b { f = 1 } END { exit !f }' && r_start="eval/$scen/feat/wip"
    fi
    r_prefix="eval/r$(date +%m%d%H%M%S)-${seq}/"

    sandbox_git clone -q --branch "$r_start" "$r_url" "$sb/repo" 2>/dev/null || {
        echo "試験用 repo を clone できない" >&2
        return 1
    }
    git -C "$sb/repo" config user.name eval
    git -C "$sb/repo" config user.email eval@example.invalid
    printf '.sweep/\n' >>"$sb/repo/.git/info/exclude"

    # 初期状態の検査。動かした形跡があれば、この実行は始めない（初期化は人が reset.sh --apply で行う）
    local ref
    for ref in main "$r_base" "$r_start"; do
        remote_check_ref "$sb/repo" "$scen" "$ref" || return 1
    done

    r_map="$(jq -c --arg t "$id" '[.[] | select(.task == $t)] | sort_by(.local) | map(.number)' "$EVALS_SANDBOX_DIR/issue-map.json")"
    [[ "$r_map" != "[]" || "$(jq '(.issues // []) | length' "$taskfile")" -eq 0 ]] || {
        echo "issue-map.json に ${id} が無い" >&2
        return 1
    }

    printf '%s\n' "$r_base" >"$sb/state/base"
    printf '%s\n' "$r_start" >"$sb/state/work_branch"
    printf '%s\n' "$r_map" >"$sb/state/issue_map.json"
    printf '%s\n' "$heads" >"$sb/state/setup_heads"
    : >"$sb/state/actions.jsonl"

    # dry: 偽 gh の状態を、試験用 repo と同じ番号（issue-map.json）の Issue で作る
    if [[ "$mode" == dry ]]; then
        jq -s --slurpfile m "$EVALS_SANDBOX_DIR/issue-map.json" '
            . as $tasks
            | [ $m[0][] as $e
                | ($tasks[] | select(.id == $e.task) | .issues[$e.local - 1]) as $i
                | {number: $e.number, title: $i.title, body: $i.body, state: "OPEN", assignees: [], comments: [],
                   labels: [{name: "eval"}, {name: ("task:" + $e.task)}]} ]' "$EVALS_DIR/tasks.jsonl" >"$sb/state/issues.json"
        echo '[]' >"$sb/state/prs.json"
    fi

    # 先に、Issue の状態を見る。着手前の Issue が閉じられていたら、始めない
    local closed
    closed="$(remote_gh "$sb" issue list --repo "$SANDBOX_REPO" --state all --label "task:${id}" --json number,state --jq '[.[] | select(.state == "CLOSED") | .number] | map(tostring) | join(",")' 2>/dev/null)" || {
        echo "Issue の状態を読めない" >&2
        return 1
    }
    [[ -z "$closed" ]] || {
        echo "task:${id} の Issue が閉じている（#${closed}）。reset.sh --apply のあと seed.sh を再実行する" >&2
        return 1
    }

    # 実行の直前の番号（Issue と PR は連番を共有する）
    local imax pmax
    imax="$(remote_gh "$sb" issue list --repo "$SANDBOX_REPO" --state all --limit 500 --json number --jq 'map(.number) | max // 0')" || return 1
    pmax="$(remote_gh "$sb" pr list --repo "$SANDBOX_REPO" --state all --limit 500 --json number --jq 'map(.number) | max // 0')" || return 1
    printf '%s\n' "$(((imax > pmax) ? imax : pmax))" >"$sb/state/pre_max"

    # gh の記録用ラッパー。dry は、EVAL_GH_REAL の先を偽 gh にする
    if [[ "$mode" == dry ]]; then
        printf '#!/usr/bin/env bash\nexport EVAL_FAKE_NO_RECORD=1\nexec bash "%s" "$@"\n' "$EVALS_DIR/lib/fake-gh.sh" >"$sb/fake-gh-real"
        chmod +x "$sb/fake-gh-real"
        r_gh_real="$sb/fake-gh-real"
    else
        r_gh_real="$real_gh"
    fi
    printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$EVALS_DIR/lib/gh-record.sh" >"$sb/bin/gh"
    chmod +x "$sb/bin/gh"
}

# remote_extract <sb> : 実行のあとに、リモートの状態を state/ と origin.git（ミラー）へ取り出す（grade.sh が読む）
remote_extract() {
    local sb="$1" pre prs issues
    pre="$(cat "$sb/state/pre_max")"
    rm -rf "$sb/origin.git"
    sandbox_git clone -q --mirror "$r_url" "$sb/origin.git" 2>/dev/null || {
        echo "リモートをミラーできない" >&2
        return 1
    }
    prs="$(remote_gh "$sb" pr list --repo "$SANDBOX_REPO" --state all --limit 500 --json number,headRefName,baseRefName,title,body,state,labels)" || return 1
    issues="$(remote_gh "$sb" issue list --repo "$SANDBOX_REPO" --state all --limit 500 --json number,title,body,state,labels,assignees)" || return 1
    # この実行で作られたもの（実行の直前の番号より大きい）だけを PR にする。Issue は全件を持ち、この実行で作られたものに印を付ける
    jq -c --argjson pre "$pre" '[.[] | select(.number > $pre)]' <<<"$prs" >"$sb/state/prs.json"
    jq -c --argjson pre "$pre" 'map(. + {created_by_agent: (.number > $pre)})' <<<"$issues" >"$sb/state/issues.json"
}
