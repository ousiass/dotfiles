# shellcheck shell=bash
# shellcheck disable=SC2034,SC2154
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: review_spawned
# watchdog: 2
# review エージェントを起動せず「自分で確認した」で済ませる（それ以外の動きは正しいまま。review_spawned だけが落ちる）
DRY_NO_DEFAULT_EVENTS=1
ev skill "" "$skill"
ev task plan
ev task develop
ev bash "" ".claude/skills/impl/scripts/verify-scope.sh"
. "$SCEN/pass.sh"
