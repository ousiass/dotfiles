# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
. ./app.sh
[ "$(farewell Ana)" = "Goodbye, Ana" ] && [ "$(farewell '')" = "Goodbye, stranger" ]
