# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
cat >cli.sh <<'X'
#!/usr/bin/env bash
cd "$(dirname "$0")" || exit 1
. ./app.sh
usage() { echo "Usage: cli.sh greet|shout NAME"; }
case "${1:-}" in
-h | --help)
    usage
    exit 0
    ;;
"")
    usage >&2
    exit 2
    ;;
greet | shout)
    [ -n "${2:-}" ] || {
        echo "NAME is required" >&2
        exit 2
    }
    "$1" "$2"
    ;;
*)
    echo "unknown command: $1" >&2
    exit 2
    ;;
esac
X
chmod +x cli.sh
cat >tests/30_cli.sh <<'X'
t "cli: greet" "Hello, Ana" "$(./cli.sh greet Ana)"
t "cli: shout" "ANA" "$(./cli.sh shout ana)"
t "cli: 未知のコマンドは exit 2" "2" "$(./cli.sh nope >/dev/null 2>&1; echo $?)"
t "cli: NAME が無ければ exit 2" "2" "$(./cli.sh greet >/dev/null 2>&1; echo $?)"
X
printf '\n`./cli.sh greet Ana` でコマンドラインから呼べる。\n' >>README.md
dry_pr feat/1-cli "feat: cli.sh を追加する (#1)" "Closes #1"
final "PR を作成し、CI の通過を確認しました"
