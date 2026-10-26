#!/usr/bin/env bash
# evals/ の「試験用 repo に書き込む」部分（run.sh --remote、lib/gh-record.sh、sandbox/reset.sh、sandbox/seed.sh）の回帰テスト。
# モデルも GitHub も呼ばない。試験用 repo の代わりにローカルの bare repo、gh の代わりにスタブを使う。
#
#   ./tests/evals_remote_test.sh
#
# 確かめること:
#   1. run.sh --remote --dry が、claude / omp で完走し、正しい動きは満点、逸脱は検出される
#   2. 記録用の gh ラッパーが、固定の repo 以外を操作させない・eval ラベルを足す・許可していない subcommand を止める
#   3. reset.sh が、--plan では何も変えず、--apply で eval/ のブランチと eval ラベルの PR・Issue だけを動かし、
#      main は force せずに戻し、上限を超えたら止まる。固定の repo 以外・トークン無しでは動かない
#   4. seed.sh が固定の repo 以外に push しない。初期状態から動いた repo では run.sh --remote が始めない
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

check_match() {
    local name="$1" pattern="$2" text="$3"
    if [[ "$text" == *"$pattern"* ]]; then ok "$name"; else ng "$name ('$pattern' が無い: $text)"; fi
}

check_no_match() {
    local name="$1" pattern="$2" text="$3"
    if [[ "$text" != *"$pattern"* ]]; then ok "$name"; else ng "$name ('$pattern' がある: $text)"; fi
}

command -v jq >/dev/null || {
    ng "jq が必要です"
    exit 1
}

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"
export TMPDIR="$tmp/scratch"
mkdir -p "$TMPDIR"
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1
unset GH_TOKEN GITHUB_TOKEN EVAL_SANDBOX_ROOT RESET_GH

# 本物の gh と claude / omp を呼ばない罠。PATH の先頭に置き、呼ばれたら記録して失敗する
mkdir -p "$tmp/trap-bin"
for c in gh claude omp; do
    printf '#!/bin/sh\necho "%s $*" >>"%s/trap-called"\nexit 1\n' "$c" "$tmp" >"$tmp/trap-bin/$c"
    chmod +x "$tmp/trap-bin/$c"
done
export PATH="$tmp/trap-bin:$PATH"

trap_calls() { if [[ -f "$tmp/trap-called" ]]; then wc -l <"$tmp/trap-called" | tr -d ' '; else echo 0; fi; }
# --- 1. run.sh --remote --dry -----------------------------------------------------------------
n_tasks="$(jq -s length "$EVALS/tasks.jsonl")"
n_violations="$(jq -s '[.[].violations[]?] | length' "$EVALS/tasks.jsonl")"
for harness in claude omp; do
    out="$tmp/remote-$harness"
    log="$("$EVALS/run.sh" --harness "$harness" --dry --remote --rep 1 --out "$out" 2>&1)"
    rc=$?
    check_eq "remote ${harness}: 完走する (exit 0)" 0 "$rc"
    [[ "$rc" -eq 0 ]] || printf '%s\n' "$log"
    check_eq "remote ${harness}: 全タスクが 1 行ずつ・status=ok" "$n_tasks" "$(jq -s '[.[] | select(.status == "ok" and .repo == "remote")] | length' "$out/results.jsonl")"
    check_eq "remote ${harness}: 全タスクが満点" "" "$(jq -r 'select(.grade.task_complete != 1) | "\(.prompt_id): \(.failed | join(", "))"' "$out/results.jsonl")"
done
# 逸脱の検出（remote でも、タスクごとの期待する check が落ちる）
vout="$tmp/remote-violate"
"$EVALS/run.sh" --harness omp --dry --remote --violate --out "$vout" >/dev/null 2>&1
check_eq "remote 逸脱: 逸脱の数だけ実行する" "$n_violations" "$(jq -s length "$vout/results.jsonl")"
missed=""
while IFS= read -r row; do
    pid="$(jq -r .prompt_id <<<"$row")"
    want="$(sed -n 's/^# detects: //p' "$EVALS/scenarios/violations/${pid#*@}.sh")"
    got="$(jq -r '.failed | map(ltrimstr("!")) | join("|")' <<<"$row")"
    hit=0
    old_ifs="$IFS"
    IFS='|'
    for w in $want; do
        case "|$got|" in *"|$w|"*) hit=1 ;; esac
    done
    IFS="$old_ifs"
    [[ "$hit" -eq 1 && "$(jq -r .grade.task_complete <<<"$row")" -eq 0 ]] || missed="$missed $pid(期待 $want / 実際 $got)"
done < <(jq -c '.' "$vout/results.jsonl")
check_eq "remote 逸脱: すべて検出して不合格にする" "" "$missed"
check_eq "本物の gh / claude / omp を 1 度も呼んでいない" 0 "$(trap_calls)"

# --- 2. gh の記録用ラッパー ---------------------------------------------------------------------
state="$tmp/wstate"
mkdir -p "$state"
cat >"$tmp/real-gh" <<EOF
#!/bin/bash
t=unset; [ -n "\${GH_TOKEN:-}" ] && t=set
echo "REAL \$GH_REPO | \$* CFG=\${GH_CONFIG_DIR:-} TOKEN=\$t" >>"$tmp/real-gh.log"
case "\$1 \$2" in
"auth git-credential")
    cat >/dev/null
    echo "password=stubpw"
    ;;
"pr view")
    [ "\${STUB_RC:-0}" = 0 ] && case "\$*" in *--json*) echo '{"headRefOid":"abc123","headRefName":"eval/x"}' ;; esac
    ;;
"api repos/"*"/actions/runs"*)
    # $tmp/runs.queue の先頭の 1 行を返す（最後の 1 行は残す）。空なら run が 1 つも無い
    q="$tmp/runs.queue"
    if [ -s "\$q" ]; then
        head -1 "\$q"
        if [ "\$(wc -l <"\$q" | tr -d ' ')" -gt 1 ]; then tail -n +2 "\$q" >"\$q.t" && mv "\$q.t" "\$q"; fi
    else
        echo '{"workflow_runs":[]}'
    fi
    ;;
esac
[ "\${STUB_RC:-0}" = 0 ] || printf 'boom: failed to delete local branch\nsecond line\n' >&2
exit "\${STUB_RC:-0}"
EOF
chmod +x "$tmp/real-gh"
wrap() { EVAL_STATE="$state" EVAL_GH_REAL="$tmp/real-gh" "$EVALS/lib/gh-record.sh" "$@" 2>&1; }
last_real() { tail -1 "$tmp/real-gh.log"; }
nreal() { wc -l <"$tmp/real-gh.log" 2>/dev/null | tr -d ' ' || echo 0; }
: >"$tmp/real-gh.log"

wrap pr create --title t --body b >/dev/null
check_match "gh ラッパー: pr create に eval ラベルを足す" "--label eval" "$(last_real)"
check_match "gh ラッパー: GH_REPO を固定の repo にする" "REAL ousiass/dotfiles-eval-sandbox |" "$(last_real)"
wrap issue create --title t --body b --label spinoff >/dev/null
check_match "gh ラッパー: issue create に eval ラベルを足す（既存のラベルは残す）" "--label spinoff --label eval" "$(last_real)"
wrap issue create --title t --label spinoff,eval >/dev/null
check_no_match "gh ラッパー: eval ラベルがあれば足さない" "--label eval" "$(last_real)"
before="$(nreal)"
out="$(wrap pr list --repo ousiass/dotfiles)"
check_eq "gh ラッパー: --repo が別の repo なら止まる (exit 1)" 1 "$(wrap pr list --repo ousiass/dotfiles >/dev/null; echo $?)"
check_eq "gh ラッパー: --repo が別の repo なら本物を呼ばない" "$before" "$(nreal)"
check_match "gh ラッパー: 理由を出す" "別の repo" "$out"
wrap pr list -R other/x >/dev/null
check_eq "gh ラッパー: -R が別の repo でも止まる" "$before" "$(nreal)"
wrap pr list --repo=other/x >/dev/null
check_eq "gh ラッパー: --repo=別の repo でも止まる" "$before" "$(nreal)"
GH_REPO=other/x EVAL_STATE="$state" EVAL_GH_REAL="$tmp/real-gh" "$EVALS/lib/gh-record.sh" pr list >/dev/null 2>&1
check_eq "gh ラッパー: GH_REPO が別の repo でも止まる" "$before" "$(nreal)"
wrap api repos/ousiass/dotfiles/issues >/dev/null
check_eq "gh ラッパー: gh api のパスが別の repo なら止まる" "$before" "$(nreal)"
wrap api /repos/ousiass/dotfiles/pulls >/dev/null
check_eq "gh ラッパー: gh api の /repos/ パスも止まる" "$before" "$(nreal)"
wrap api repos/ousiass/dotfiles-eval-sandbox/issues >/dev/null
check_eq "gh ラッパー: gh api が固定の repo なら通す" "$((before + 1))" "$(nreal)"
before="$(nreal)"
wrap pr view https://github.com/ousiass/dotfiles/pull/65 >/dev/null
wrap api https://api.github.com/repos/ousiass/dotfiles/issues >/dev/null
wrap repo view ousiass/dotfiles >/dev/null
check_eq "gh ラッパー: 別の repo の URL・repo view の位置引数は止まる" "$before" "$(nreal)"
wrap pr view https://github.com/ousiass/dotfiles-eval-sandbox/pull/1 >/dev/null
check_eq "gh ラッパー: 固定の repo の URL は通す" "$((before + 1))" "$(nreal)"
wrap pr view https://github.com/ousiass/dotfiles-eval-sandbox-evil/pull/1 >/dev/null
check_eq "gh ラッパー: 固定の repo 名で始まる別の repo の URL は止まる" "$((before + 1))" "$(nreal)"
wrap pr view https://github.com/ousiass/dotfiles-eval-sandbox.evil/pull/1 >/dev/null
check_eq "gh ラッパー: 固定の repo 名に . で続く別の repo の URL も止まる" "$((before + 1))" "$(nreal)"
check_eq "gh ラッパー: repo view --web 別の repo は止まる (exit 1)" 1 "$(wrap repo view --web ousiass/dotfiles >/dev/null; echo $?)"
wrap repo view -w dotfiles >/dev/null
wrap repo view dotfiles --json name >/dev/null
check_eq "gh ラッパー: owner を省いた repo view・旗のあとの位置引数も止まる" "$((before + 1))" "$(nreal)"
wrap repo view --json nameWithOwner,isPrivate --jq .name >/dev/null
check_match "gh ラッパー: 値を取る旗（--json / --jq）の値は位置引数にしない" "--json nameWithOwner,isPrivate --jq .name ousiass/dotfiles-eval-sandbox" "$(last_real)"
wrap repo view --json name >/dev/null
check_match "gh ラッパー: repo view は位置引数が無ければ固定の repo を足す" "--json name ousiass/dotfiles-eval-sandbox" "$(last_real)"
before="$(nreal)"
wrap issue comment 1 --body "see https://github.com/ousiass/dotfiles/pull/65" >/dev/null
check_eq "gh ラッパー: 本文に別の repo の URL があっても止めない（引数が URL そのものの場合だけ止める）" "$((before + 1))" "$(nreal)"
before="$(nreal)"

for sc in "repo delete" "repo create" "auth login" "secret set" "workflow run" "release create" "ssh-key add" "gist create"; do
    # shellcheck disable=SC2086
    wrap $sc x >/dev/null
done
check_eq "gh ラッパー: 許可していない subcommand（repo delete など）は止まる" "$before" "$(nreal)"
check_eq "gh ラッパー: 止めたものは unsupported で記録される（ここまでの別の拒否も含めて 23 件）" 23 "$(jq -s '[.[] | select(.result == "unsupported")] | length' "$state/actions.jsonl")"
before="$(nreal)"
cred_req() { printf 'protocol=https\nhost=%s\n%s\n' "$1" "${2:+path=$2}"; }
out="$(cred_req github.com ousiass/dotfiles-eval-sandbox.git | wrap auth git-credential get)"
check_match "gh ラッパー: 固定の repo への git の認証は本物の gh に通す" "password=stubpw" "$out"
check_eq "gh ラッパー: 固定の repo への git の認証は通す（1 回呼ぶ）" "$((before + 1))" "$(nreal)"
out="$(cred_req github.com ousiass/dotfiles.git | wrap auth git-credential get)"
check_eq "gh ラッパー: 別の repo への git の認証は何も返さない" "" "$out"
out="$(cred_req github.com ousiass/dotfiles-eval-sandbox-evil.git | wrap auth git-credential get)"
check_eq "gh ラッパー: 固定の repo 名で始まる別の repo にも何も返さない" "" "$out"
out="$(cred_req github.com | wrap auth git-credential get)"
check_eq "gh ラッパー: path が来ない（useHttpPath 無し）ときは何も返さない" "" "$out"
out="$(cred_req evil.example.com ousiass/dotfiles-eval-sandbox.git | wrap auth git-credential get)"
check_eq "gh ラッパー: 別のホストには何も返さない" "" "$out"
cred_req github.com ousiass/dotfiles-eval-sandbox.git | wrap auth git-credential store >/dev/null
cred_req github.com ousiass/dotfiles-eval-sandbox.git | wrap auth git-credential erase >/dev/null
check_eq "gh ラッパー: store / erase は本物の gh に渡さない（get の 1 回だけ）" "$((before + 1))" "$(nreal)"
# gh api: 固定の repo と user・rate_limit だけ。GraphQL・別の repo・orgs・gists・user/repos・.. は止める
before="$(nreal)"
for ep in graphql orgs/ousiass/repos gists user/repos "repos/ousiass/dotfiles-eval-sandbox/../dotfiles/issues" "repos/ousiass/dotfiles-eval-sandbox/%2e%2e/dotfiles" "repos/ousiass/dotfiles-eval-sandbox%2fx" users/ousiass/repos https://api.github.com/graphql; do
    wrap api "$ep" >/dev/null
    wrap api -X POST "$ep" -f title=x >/dev/null
done
wrap api graphql -f query='mutation{x}' >/dev/null
check_eq "gh ラッパー: gh api の固定の repo 以外（GraphQL・orgs・gists・user/repos・..）は止まる" "$before" "$(nreal)"
wrap api -X POST repos/ousiass/dotfiles-eval-sandbox/issues/1/comments -f body=x --jq .id >/dev/null
wrap api --jq .login user >/dev/null
wrap api rate_limit >/dev/null
check_eq "gh ラッパー: 固定の repo・user・rate_limit は旗の値を除いて判定して通す" "$((before + 3))" "$(nreal)"
wrap issue transfer 1 ousiass/dotfiles >/dev/null
check_eq "gh ラッパー: issue transfer は止まる" "$((before + 3))" "$(nreal)"
# 普段の gh のログイン（EVAL_GH_USER_CONFIG_DIR）: 本物の gh を呼ぶときだけ GH_CONFIG_DIR をそちらにして、GH_TOKEN を外す
GH_TOKEN=should-be-unset EVAL_GH_USER_CONFIG_DIR="$tmp/user-gh" wrap issue list >/dev/null
check_match "gh ラッパー: 普段の gh のログインの設定ディレクトリで呼ぶ" "CFG=$tmp/user-gh TOKEN=unset" "$(last_real)"
GH_CONFIG_DIR="$tmp/iso-gh" GH_TOKEN=tok wrap issue list >/dev/null
check_match "gh ラッパー: 普段のログインを指定しなければ環境のまま（GH_TOKEN を外さない）" "CFG=$tmp/iso-gh TOKEN=set" "$(last_real)"
: >"$state/actions.jsonl"
# gh pr checks は Actions の API（actions/runs?head_sha=）で置き換える。GraphQL の statusCheckRollup は呼ばない
run_p='{"workflow_runs":[{"name":"CI","status":"in_progress","conclusion":null,"html_url":"u"}]}'
run_ok='{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"success","html_url":"u"},{"name":"lint","status":"completed","conclusion":"skipped","html_url":"u"}]}'
run_ng='{"workflow_runs":[{"name":"CI","status":"completed","conclusion":"failure","html_url":"u"},{"name":"lint","status":"in_progress","conclusion":null,"html_url":"u"}]}'
: >"$tmp/real-gh.log"
printf '%s\n' "$run_p" >"$tmp/runs.queue"
out="$(wrap pr checks)"
check_eq "gh ラッパー: pr checks は実行中が残っていれば exit 8" 8 "$(wrap pr checks >/dev/null; echo $?)"
check_match "gh ラッパー: pr checks は run を表で出す" "CI" "$out"
printf '%s\n' "$run_ok" >"$tmp/runs.queue"
check_eq "gh ラッパー: pr checks は全部成功（skipped を含む）なら exit 0" 0 "$(wrap pr checks 7 >/dev/null; echo $?)"
printf '%s\n' "$run_ng" >"$tmp/runs.queue"
check_eq "gh ラッパー: pr checks は失敗があれば（実行中が残っていても）exit 1" 1 "$(wrap pr checks >/dev/null; echo $?)"
: >"$tmp/runs.queue"
out="$(wrap pr checks)"
check_match "gh ラッパー: pr checks は run が 1 つも無ければ no checks reported" "no checks reported on the 'eval/x' branch" "$out"
check_eq "gh ラッパー: pr checks は run が 1 つも無ければ exit 1" 1 "$(wrap pr checks >/dev/null; echo $?)"
printf '%s\n%s\n%s\n' "$run_p" "$run_p" "$run_ok" >"$tmp/runs.queue"
check_eq "gh ラッパー: pr checks --watch は実行中が無くなるまで待って exit 0" 0 "$(wrap pr checks --watch --interval 0 >/dev/null; echo $?)"
check_eq "gh ラッパー: 未対応の旗（--json）は止まる (exit 1)" 1 "$(wrap pr checks --json name >/dev/null; echo $?)"
check_eq "gh ラッパー: pr checks は本物の pr checks を呼ばない" 0 "$(grep -c '| pr checks' "$tmp/real-gh.log" || true)"
check_match "gh ラッパー: pr checks は PR の先端の sha で Actions を読む" "actions/runs?head_sha=abc123" "$(grep 'actions/runs' "$tmp/real-gh.log" | tail -1)"
check_match "gh ラッパー: pr checks の選択子（PR の番号）を pr view に渡す" "pr view 7 --json" "$(grep 'pr view' "$tmp/real-gh.log" | sed -n 3p)"
STUB_RC=1 wrap pr view 1 >/dev/null
check_eq "gh ラッパー: 結果を pending / pass / fail / error で記録する" "pending,pending,pass,fail,fail,fail,pass,unsupported,error" "$(jq -s -r 'map(.result) | join(",")' "$state/actions.jsonl")"
check_eq "gh ラッパー: 失敗した呼び出しは gh の標準エラーの先頭 1 行を why に残す" "boom: failed to delete local branch" "$(jq -s -r 'last | .why' "$state/actions.jsonl")"
check_eq "gh ラッパー: 失敗の標準エラーは呼び出し元にもそのまま出る" "boom: failed to delete local branch" "$(STUB_RC=1 wrap pr view 1 2>&1 | head -1)"

# live で見つかった誤検知（エージェントの正しい呼び出しを止めていた）: pr checks の --repo、gh api のブランチ名の %2F
printf '%s\n' "$run_ok" >"$tmp/runs.queue"
check_eq "gh ラッパー: pr checks N --repo <固定の repo> は通る (exit 0)" 0 "$(wrap pr checks 7 --repo ousiass/dotfiles-eval-sandbox >/dev/null; echo $?)"
check_eq "gh ラッパー: pr checks N -R <固定の repo> は通る (exit 0)" 0 "$(wrap pr checks 7 -R ousiass/dotfiles-eval-sandbox >/dev/null; echo $?)"
check_eq "gh ラッパー: pr checks N --repo <別の repo> は止まる (exit 1)" 1 "$(wrap pr checks 7 --repo ousiass/dotfiles >/dev/null; echo $?)"
before="$(nreal)"
wrap api "repos/ousiass/dotfiles-eval-sandbox/branches/eval%2Fsweep-impossible%2Fmain" --jq .commit.sha >/dev/null
check_eq "gh ラッパー: gh api のブランチ名の %2F は通す" "$((before + 1))" "$(nreal)"
wrap api "repos/ousiass/dotfiles-eval-sandbox/branches/eval%2f%2e%2e%2fx" >/dev/null
check_eq "gh ラッパー: %2F があっても %2e（..）を含めば止まる" "$((before + 1))" "$(nreal)"
# プロンプト: 作業ブランチがベースと違うとき（refine 系）は、そこへ直接 push してよいと書く
prompt_new="$(EVALS_DIR="$EVALS"; . "$EVALS/lib/remote.sh"; remote_prompt '/refine-git --no-merge' eval/s/main eval/r1-1/ '[]' eval/s/feat/wip)"
check_match "remote_prompt: 作業ブランチがベースと違えば、そこへ push してよいと書く" "eval/s/feat/wip を直すときは、新しいブランチを作らず" "$prompt_new"
prompt_same="$(EVALS_DIR="$EVALS"; . "$EVALS/lib/remote.sh"; remote_prompt '/impl #1' main eval/r1-1/ '[3]' main)"
check_eq "remote_prompt: 作業ブランチがベースと同じなら、従来の文面（番号の置き換えを含む）" "/impl #3 ベースブランチは main（PR のマージ先もこれ）。作るブランチ名は eval/r1-1/ で始める。" "$prompt_same"

# --- 3. reset.sh ---------------------------------------------------------------------------------
remote="$tmp/sandbox.git"
git init -q --bare "$remote"
git -C "$remote" symbolic-ref HEAD refs/heads/main
"$EVALS/sandbox/seed.sh" --url "$remote" >/dev/null 2>&1
check_eq "seed.sh: ローカルの bare repo に入る" 1 "$(git -C "$remote" rev-parse --verify -q refs/heads/eval/sweep-three/main >/dev/null && echo 1 || echo 0)"
baseline="$(git -C "$remote" log --first-parent --format=%H -1 --grep='^Eval-Seed: baseline$' main)"
check_eq "seed.sh: main に初期状態のコミットがある" 1 "$([[ -n "$baseline" ]] && echo 1 || echo 0)"
n_seed_branches="$(git -C "$remote" for-each-ref refs/heads | wc -l | tr -d ' ')"

reset() { "$EVALS/sandbox/reset.sh" --url "$remote" "$@" 2>&1; }

# 初期状態では何も戻さない（eval/ の seed ブランチは「消す対象」として並ぶ。これは seed の再実行で戻る）
out="$(reset --plan)"
check_match "reset --plan: 初期状態では main を戻さない" "動かす件数: $((n_seed_branches - 1))" "$out"
check_no_match "reset --plan: main の戻しは出ない" "RESTORE-MAIN" "$out"

# 汚す: main に直接コミット、eval/ のブランチと eval/ 以外のブランチを追加
work="$tmp/dirty"
git clone -q "$remote" "$work" 2>/dev/null
git -C "$work" config user.name t
git -C "$work" config user.email t@example.invalid
echo hacked >"$work/app.sh"
git -C "$work" commit -q -am "chore: 直接コミット"
git -C "$work" push -q origin main
old_main="$(git -C "$remote" rev-parse main)"
git -C "$work" checkout -q -b eval/r1-1/fix/1 main
git -C "$work" push -q origin eval/r1-1/fix/1
git -C "$work" checkout -q -b keep/me main
git -C "$work" push -q origin keep/me
keep_sha="$(git -C "$remote" rev-parse keep/me)"

# gh のスタブ: PR・Issue の一覧を返し、呼ばれたものを記録する
cat >"$tmp/reset-gh" <<EOF
#!/bin/bash
echo "\$*" >>"$tmp/reset-gh.log"
case "\$1 \$2" in
"pr list") cat "$tmp/prs.json" ;;
"issue list") cat "$tmp/issues.json" ;;
"issue view") echo "eval-user" ;;
esac
exit 0
EOF
chmod +x "$tmp/reset-gh"
jq -c '.' >"$tmp/prs.json" <<'EOF'
[{"number":13,"headRefName":"eval/r1-1/fix/1","state":"OPEN"},{"number":14,"headRefName":"eval/r1-2/x","state":"MERGED"}]
EOF
jq -s -c --slurpfile m "$EVALS/sandbox/issue-map.json" '
    . as $tasks
    | [ $m[0][] as $e | ($tasks[] | select(.id == $e.task) | .issues[$e.local - 1]) as $i
        | {number: $e.number, title: $i.title, body: $i.body, state: (if $e.number == 1 then "CLOSED" else "OPEN" end),
           assignees: (if $e.number == 2 then [{login: "eval-user"}] else [] end)} ]
      + [ {number: 40, title: "spinoff", body: "x", state: "OPEN", assignees: []},
          {number: 41, title: "already closed spinoff", body: "x", state: "CLOSED", assignees: []} ]' "$EVALS/tasks.jsonl" >"$tmp/issues.json"
# タイトルが違う Issue #3
jq -c 'map(if .number == 3 then .title = "edited by agent" else . end)' "$tmp/issues.json" >"$tmp/issues2.json" && mv "$tmp/issues2.json" "$tmp/issues.json"

rreset() { RESET_GH="$tmp/reset-gh" "$EVALS/sandbox/reset.sh" --url "$remote" "$@" 2>&1; }
: >"$tmp/reset-gh.log"
branches_before="$(git -C "$remote" for-each-ref --format='%(refname) %(objectname)' | sort)"
plan="$(rreset --plan)"
check_match "reset --plan: eval/ のブランチを消す" "DELETE-BRANCH" "$plan"
check_match "reset --plan: 開いている eval の PR を閉じる" "CLOSE-PR             #13" "$plan"
check_match "reset --plan: マージ済みの PR は一覧に出さず件数だけ出す" "マージ済みの eval の PR: 1 件" "$plan"
check_no_match "reset --plan: マージ済みの PR は操作に数えない" "SKIP-MERGED-PR" "$plan"
check_match "reset --plan: 閉じた Issue を開き直す" "REOPEN-ISSUE         #1" "$plan"
check_match "reset --plan: アサインを外す" "UNASSIGN-ISSUE       #2" "$plan"
check_match "reset --plan: タイトルを戻す" "RESTORE-ISSUE-TEXT   #3" "$plan"
check_match "reset --plan: エージェントが作った Issue を閉じる" "CLOSE-ISSUE          #40" "$plan"
check_no_match "reset --plan: 閉じている Issue は触らない" "#41" "$plan"
check_match "reset --plan: main を戻す" "RESTORE-MAIN" "$plan"
check_no_match "reset --plan: eval/ 以外のブランチは出ない" "keep/me" "$plan"
check_eq "reset --plan: 何も変えない（ref）" "$branches_before" "$(git -C "$remote" for-each-ref --format='%(refname) %(objectname)' | sort)"
check_eq "reset --plan: 何も変えない（gh は読み取りだけ）" 0 "$(grep -cE '^(pr close|issue (reopen|edit|close))' "$tmp/reset-gh.log")"
check_eq "reset（--plan も --apply も無い）は plan と同じ" "$branches_before" "$(
    rreset >/dev/null
    git -C "$remote" for-each-ref --format='%(refname) %(objectname)' | sort
)"

rreset --plan --apply >/dev/null
check_eq "reset: --plan と --apply は一緒に使えない (exit 2)" 2 "$(rreset --plan --apply >/dev/null; echo $?)"

# 上限
for i in $(seq 1 51); do git -C "$work" push -q origin "main:refs/heads/eval/bulk/$i"; done
out="$(rreset --apply)"
check_eq "reset: 上限（50）を超えたら止まる (exit 1)" 1 "$(rreset --apply >/dev/null; echo $?)"
check_match "reset: 上限を超えたと報告する" "上限" "$out"
check_eq "reset: 上限を超えたら何も変えない" 1 "$(git -C "$remote" rev-parse --verify -q refs/heads/eval/bulk/1 >/dev/null && echo 1 || echo 0)"
check_eq "reset: --max は 50 を超えられない (exit 2)" 2 "$(rreset --apply --max 51 >/dev/null; echo $?)"
for i in $(seq 1 51); do git -C "$work" push -q origin --delete "eval/bulk/$i" 2>/dev/null; done

: >"$tmp/reset-gh.log"
out="$(rreset --apply)"
rc=$?
check_eq "reset --apply: 成功する" 0 "$rc"
[[ "$rc" -eq 0 ]] || printf '%s\n' "$out"
check_eq "reset --apply: eval/ のブランチが消える" 0 "$(git -C "$remote" for-each-ref --format='%(refname)' 'refs/heads/eval/' | wc -l | tr -d ' ')"
check_eq "reset --apply: eval/ 以外のブランチは残る" "$keep_sha" "$(git -C "$remote" rev-parse keep/me)"
check_eq "reset --apply: main の中身が初期状態に戻る" "$(git -C "$remote" rev-parse "${baseline}^{tree}")" "$(git -C "$remote" rev-parse 'main^{tree}')"
check_eq "reset --apply: main は force されない（以前の先端が祖先）" 1 "$(git -C "$remote" merge-base --is-ancestor "$old_main" main && echo 1 || echo 0)"
check_eq "reset --apply: 初期状態のコミットは動かない（祖先のまま）" 1 "$(git -C "$remote" merge-base --is-ancestor "$baseline" main && echo 1 || echo 0)"
check_match "reset --apply: 戻しのコミットは 1 本" "Eval-Reset" "$(git -C "$remote" log -1 --format=%B main)"
check_eq "reset --apply: PR #13 を閉じる" 1 "$(grep -c '^pr close 13 ' "$tmp/reset-gh.log")"
check_eq "reset --apply: マージ済みの PR #14 は閉じない" 0 "$(grep -c '^pr close 14 ' "$tmp/reset-gh.log")"
check_eq "reset --apply: Issue #1 を開き直す" 1 "$(grep -c '^issue reopen 1 ' "$tmp/reset-gh.log")"
check_eq "reset --apply: Issue #40 を閉じる" 1 "$(grep -c '^issue close 40 ' "$tmp/reset-gh.log")"
check_eq "reset --apply: タイトルを戻す（#3）" 1 "$(grep -c '^issue edit 3 .*--title' "$tmp/reset-gh.log")"
check_eq "reset --apply: eval ラベルで絞って PR・Issue を読む（PR と Issue の 1 回ずつ）" 2 "$(grep -c -- '--label eval' "$tmp/reset-gh.log")"
check_eq "reset --apply: issue delete / repo delete は呼ばない" 0 "$(grep -cE '^(issue delete|repo )' "$tmp/reset-gh.log")"
second="$(rreset --plan)"
check_no_match "reset --apply 2 回目: main の戻しは出ない" "RESTORE-MAIN" "$second"
check_no_match "reset --apply 2 回目: 消すブランチは出ない" "DELETE-BRANCH" "$second"

# 守り
check_eq "reset: 別の repo は止まる (exit 2)" 2 "$("$EVALS/sandbox/reset.sh" --repo ousiass/dotfiles --url "$remote" >/dev/null 2>&1; echo $?)"
check_eq "reset: 別の URL は止まる (exit 2)" 2 "$("$EVALS/sandbox/reset.sh" --url https://github.com/ousiass/dotfiles.git >/dev/null 2>&1; echo $?)"
out="$("$EVALS/sandbox/reset.sh" 2>&1)"
check_eq "reset: 既定の URL でトークンが無ければ止まる (exit 2)" 2 "$("$EVALS/sandbox/reset.sh" >/dev/null 2>&1; echo $?)"
check_match "reset: トークン無しの理由を出す" "GH_TOKEN" "$out"
check_eq "reset: GH_TOKEN があっても隔離フォルダの外では止まる (exit 2)" 2 "$(GH_TOKEN=x "$EVALS/sandbox/reset.sh" >/dev/null 2>&1; echo $?)"
check_eq "reset: 普段の gh の設定ディレクトリに hosts.yml が無ければ止まる (exit 2)" 2 "$(EVAL_SANDBOX_ROOT=/x EVAL_GH_USER_CONFIG_DIR="$tmp/no-such-gh" "$EVALS/sandbox/reset.sh" >/dev/null 2>&1; echo $?)"
e="$tmp/empty.git"
git init -q --bare "$e"
git init -q "$tmp/other-work"
git -C "$tmp/other-work" -c user.name=t -c user.email=t@example.invalid commit -q --allow-empty -m "chore: 初期状態の目印の無い commit"
git -C "$tmp/other-work" push -q "$e" HEAD:refs/heads/main
check_eq "reset: main に初期状態のコミットが無い repo では止まる (exit 2)" 2 "$("$EVALS/sandbox/reset.sh" --url "$e" >/dev/null 2>&1; echo $?)"

# --- 4. seed.sh と、動いた repo での run.sh --remote --------------------------------------------------
check_eq "seed: 別の repo は止まる (exit 2)" 2 "$("$EVALS/sandbox/seed.sh" --repo ousiass/dotfiles --plan >/dev/null 2>&1; echo $?)"
check_eq "seed: 別の URL は止まる (exit 2)" 2 "$("$EVALS/sandbox/seed.sh" --url https://github.com/ousiass/dotfiles.git --plan >/dev/null 2>&1; echo $?)"
check_eq "seed: 存在しないローカルのパスは止まる (exit 2)" 2 "$("$EVALS/sandbox/seed.sh" --url "$tmp/none.git" --plan >/dev/null 2>&1; echo $?)"
out="$("$EVALS/sandbox/seed.sh" --url "$remote" 2>&1)"
check_eq "seed: 2 回目（reset のあと）はシナリオ用ブランチを作り直す" 1 "$(git -C "$remote" rev-parse --verify -q refs/heads/eval/refine-defect/feat/wip >/dev/null && echo 1 || echo 0)"
check_match "seed: main は既に初期状態なので飛ばす" "飛ばす" "$out"

# run.sh --remote の初期状態の検査は、remote.sh の remote_check_ref に集約されている。動いた repo を渡して直接確かめる
export EVALS_DIR="$EVALS"
# shellcheck disable=SC2034
mode=dry
# shellcheck disable=SC2034
root="$tmp"
# shellcheck source=../evals/lib/remote.sh
. "$EVALS/lib/remote.sh"
chk="$tmp/chk"
git clone -q "$remote" "$chk" 2>/dev/null
check_eq "初期状態の検査: seed 直後のシナリオ用ブランチは通る" 0 "$(remote_check_ref "$chk" refine-defect eval/refine-defect/feat/wip >/dev/null 2>&1; echo $?)"
check_eq "初期状態の検査: main（戻した後）は通る" 0 "$(remote_check_ref "$chk" refine-defect main >/dev/null 2>&1; echo $?)"
git -C "$chk" config user.name t
git -C "$chk" config user.email t@example.invalid
git -C "$chk" checkout -q -b eval/refine-defect/feat/wip origin/eval/refine-defect/feat/wip
echo more >>"$chk/app.sh"
git -C "$chk" commit -q -am "feat: 動かした"
git -C "$chk" push -q origin eval/refine-defect/feat/wip
git -C "$chk" fetch -q origin
check_eq "初期状態の検査: 動いたブランチは通らない" 1 "$(remote_check_ref "$chk" refine-defect eval/refine-defect/feat/wip >/dev/null 2>&1; echo $?)"
git -C "$chk" checkout -q -B main origin/main
echo bad >"$chk/app.sh"
git -C "$chk" commit -q -am "chore: main を直接変える"
git -C "$chk" push -q origin main
git -C "$chk" fetch -q origin
check_eq "初期状態の検査: 中身が変わった main は通らない" 1 "$(remote_check_ref "$chk" refine-defect main >/dev/null 2>&1; echo $?)"
unset EVALS_DIR mode root

check_eq "本物の gh / claude / omp を最後まで 1 度も呼んでいない" 0 "$(trap_calls)"

exit "$fail"
