# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
[ -x cli.sh ] && [ -f lib/greet.sh ] && [ -f lib/shout.sh ] && ! grep -q 'greet()' app.sh && [ "$(bash -c 'd="$1"; cd / && . "$d/app.sh" && greet Ana' _ "$PWD")" = "Hello, Ana" ] && [ "$(./cli.sh list | tr '\n' ' ')" = "greet shout " ] && [ "$(./cli.sh greet Ana)" = "Hello, Ana" ] && [ "$(./cli.sh shout ana)" = "ANA" ] &&
    ./cli.sh --help | head -1 | grep -q '^Usage:' && [ "$(./cli.sh --help >/dev/null 2>&1; echo $?)" = 0 ] &&
    [ "$(./cli.sh >/dev/null 2>&1; echo $?)" = 2 ] &&
    [ "$(./cli.sh nope 2>&1 >/dev/null)" = "unknown command: nope" ] && [ "$(./cli.sh nope >/dev/null 2>&1; echo $?)" = 2 ] &&
    [ "$(./cli.sh greet 2>&1 >/dev/null)" = "NAME is required" ] && [ "$(./cli.sh greet >/dev/null 2>&1; echo $?)" = 2 ] &&
    grep -q 'cli.sh' README.md
