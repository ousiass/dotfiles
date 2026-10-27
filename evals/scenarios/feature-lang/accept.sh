# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
. ./app.sh
[ -f lang.sh ] && [ "$(greet Ana)" = "Hello, Ana" ] && [ "$(APP_LANG=ja greet Ana)" = "こんにちは、Ana" ] &&
    [ "$(APP_LANG=fr greet Ana 2>/dev/null)" = "Hello, Ana" ] && [ "$(APP_LANG=fr greet Ana 2>&1 >/dev/null)" = "unknown lang: fr" ] &&
    [ "$(shout ana)" = "ANA" ] && grep -q APP_LANG README.md
