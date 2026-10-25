#!/usr/bin/env bash
# テスト用 repo（サンドボックス）の作成。run.sh から source される。本番の GitHub にも手元の repo にも触れない。
#
#   fixture_make <sandbox> <task.json>
#
# 作るもの（すべて <sandbox> の下）:
#   origin.git   ローカルの bare repo（push 先。ネットワークに出ない）
#   repo         origin.git の clone（エージェントの作業ディレクトリ）。main に初期コミット済み
#   bin/gh       偽の gh（evals/lib/fake-gh.sh）。PATH の先頭に置く前提
#   state/       偽 gh の状態（issues.json / prs.json / actions.jsonl）と setup_heads（setup 直後の origin の各ブランチ）
#   home/        採点でだけ使う HOME（verify-scope.sh のキャッシュが実 HOME に出ないように）
#
# タスク行の `scenario` が evals/scenarios/<name>/ を指す。setup.sh があれば repo の中で実行され、
# 終わったあとに変更があればコミットして push する。`issues` はダミー Issue の配列。

# 題材は小さな bash ライブラリ。test.sh は tests/*.sh を読み、1 つでも落ちれば exit 1。
fixture_seed_files() {
    mkdir -p tests
    cat >app.sh <<'EOF'
#!/usr/bin/env bash
# eval 用の題材（小さな bash ライブラリ）
greet() { echo "Hello, $1"; }
shout() { echo "$1" | tr a-z A-Z; }
EOF
    cat >test.sh <<'EOF'
#!/usr/bin/env bash
set -u
cd "$(dirname "$0")" || exit 1
. ./app.sh
fail=0
t() {
    if [ "$2" = "$3" ]; then echo "PASS $1"; else echo "FAIL $1 (want [$2] got [$3])"; fail=1; fi
}
for f in tests/*.sh; do
    [ -f "$f" ] && . "$f"
done
exit "$fail"
EOF
    chmod +x test.sh
    echo 't "greet: 名前あり" "Hello, Ana" "$(greet Ana)"' >tests/00_greet.sh
    printf '# fixture\n\n## Usage\n\n`. ./app.sh; greet Ana`\n' >README.md
}

# サンドボックスの git は、ホストの設定（core.excludesfile・commit.gpgsign・core.hooksPath・init.templateDir など）を読まない。
# 読むと、ホストごとに採点が変わる（開発ホストの excludesfile が .sweep/ を隠して、別の環境でだけ落ちる、など）。
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

fixture_make() {
    local sb="$1" task="$2" scen setup
    mkdir -p "$sb/bin" "$sb/state" "$sb/home"
    git init -q --bare "$sb/origin.git"
    git -C "$sb/origin.git" symbolic-ref HEAD refs/heads/main
    git clone -q "$sb/origin.git" "$sb/repo" 2>/dev/null
    (
        cd "$sb/repo" || exit 1
        git config user.name "eval"
        git config user.email "eval@example.invalid"
        # 実スキルの運用に合わせ、.sweep/ はコミットに入れない（本物の repo は .gitignore に持つ）
        printf '.sweep/\n' >>"$sb/repo/.git/info/exclude"
        git checkout -q -b main
        fixture_seed_files
        git add -A
        git commit -q -m "chore: 初期コミット"
        git push -q -u origin main 2>/dev/null
        scen="$(jq -r '.scenario // ""' "$task")"
        setup="$EVALS_DIR/scenarios/$scen/setup.sh"
        if [[ -n "$scen" && -f "$setup" ]]; then
            # shellcheck source=/dev/null
            . "$setup"
            git add -A
            git diff --cached --quiet || git commit -q -m "chore: シナリオの初期状態 ($scen)"
            git push -q origin HEAD 2>/dev/null
        fi
        git -C "$sb/origin.git" for-each-ref --format='%(refname:short) %(objectname)' refs/heads >"$sb/state/setup_heads"
    ) || return 1
    jq '(.issues // []) | to_entries | map(.value + {number: (.value.number // (.key + 1)), state: "OPEN", assignees: [], comments: [], labels: ((.value.labels // []) | map({name: .}))})' "$task" >"$sb/state/issues.json"
    echo '[]' >"$sb/state/prs.json"
    : >"$sb/state/actions.jsonl"
    printf '#!/usr/bin/env bash\nexec bash "%s" "$@"\n' "$EVALS_DIR/lib/fake-gh.sh" >"$sb/bin/gh"
    chmod +x "$sb/bin/gh"
}
