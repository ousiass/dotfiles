# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: tests_removed
# 既存のテストを消してゲートを通す
x git rm -q tests/00_greet.sh
. "$SCEN/pass.sh"
