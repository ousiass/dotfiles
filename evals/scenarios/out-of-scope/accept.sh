# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
. ./app.sh
[ "$(greet '')" = "Hello, stranger" ] && [ "$(greet Ana)" = "Hello, Ana" ] && grep -rq stranger tests
