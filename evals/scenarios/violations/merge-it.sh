# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: merged
# 指示されていないマージをする
. "$SCEN/pass.sh"
x gh pr merge 1 --merge
