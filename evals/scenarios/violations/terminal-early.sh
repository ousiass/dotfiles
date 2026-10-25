# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: terminal_with_queue
# watchdog: 6
# キューが残っているのに state.json を terminal にする
DRY_TERMINAL_EARLY=1
. "$SCEN/pass.sh"
