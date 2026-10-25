# shellcheck shell=bash
# evals/sandbox の共通部分（source して使う）。試験用 repo の名前をここに固定する。
# seed.sh / reset.sh / lib/gh-record.sh / lib/remote.sh は、ここで決めた repo にしか動かない。

SANDBOX_REPO=ousiass/dotfiles-eval-sandbox
SANDBOX_URL="https://github.com/${SANDBOX_REPO}.git"
# 初期状態の目印（seed.sh が作るコミットのメッセージに入れる）。main を戻すときの「戻し先」はこのコミットの中身
SANDBOX_BASELINE_TRAILER='Eval-Seed: baseline'

# sandbox_fail <message> : 呼んだスクリプトの名前つきで出して終わる
sandbox_fail() {
    echo "$(basename "$0"): $*" >&2
    exit 2
}

# sandbox_require_repo <OWNER/NAME> : 固定の repo 以外が渡されたら止まる
sandbox_require_repo() {
    [[ "$1" == "$SANDBOX_REPO" ]] || sandbox_fail "対象は ${SANDBOX_REPO} だけです（渡された: ${1:-（空）}）"
}

# sandbox_is_local_url <url> : ローカルのパスか（配線の確認とテスト用。ネットワークに出ない）
sandbox_is_local_url() { [[ "$1" == /* ]]; }

# sandbox_require_url <url> : 固定の repo の URL か、実在するローカルの bare repo だけを許す
sandbox_require_url() {
    case "$1" in
    "$SANDBOX_URL" | "https://github.com/${SANDBOX_REPO}") ;;
    /*) [[ -d "$1" ]] || sandbox_fail "ローカルの URL が無い: $1" ;;
    *) sandbox_fail "push 先は ${SANDBOX_URL} かローカルのパスだけです（渡された: $1）" ;;
    esac
}

# 認証は gh の credential helper を通す（トークンは環境変数 GH_TOKEN から来る。ローカルのパスでは使われない）
sandbox_git() { git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"; }

# sandbox_baseline <repo> <ref> : <ref> の first-parent をたどって、最も新しい「初期状態」のコミットを出す（無ければ空）
sandbox_baseline() {
    git -C "$1" log --first-parent --format=%H -1 --grep="^${SANDBOX_BASELINE_TRAILER}\$" "$2" 2>/dev/null
}

# sandbox_ci_workflow : 試験用 repo の CI（test.sh を回すだけ）
sandbox_ci_workflow() {
    cat <<'EOF'
name: CI

on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v5
      - name: test.sh
        run: ./test.sh
EOF
}
