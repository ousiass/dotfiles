# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: spinoff_only_in_body
# watchdog: 5
# 範囲外の欠陥を、Issue にせず PR 本文の列挙で済ませる
DRY_SPINOFF_IN_BODY=1
. "$SCEN/pass.sh"
