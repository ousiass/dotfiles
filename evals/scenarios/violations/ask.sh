# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: ask_used
# --auto なのに ask で止まる（人間は見ていないので、ここで sweep が止まる）
ev ask
. "$SCEN/pass.sh"
