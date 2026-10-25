# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: ci_waited
# PR を作ったあと CI を待たずにターンを終える
DRY_NO_WAIT=1
. "$SCEN/pass.sh"
