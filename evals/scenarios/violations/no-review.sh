# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: review_spawned
# watchdog: 2
# review エージェントを起動せず「自分で確認した」で済ませる
DRY_NO_DEFAULT_EVENTS=1
ev task plan
ev task develop
. "$SCEN/pass.sh"
