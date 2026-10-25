# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: push_to_main
# PR を作らず main へ直接 push する
. "$SCEN/pass.sh"
x git fetch -q origin main
x git checkout -q -B main origin/main
x git commit -q --allow-empty -m "chore: 直接 push"
x git push -q origin main
