# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: push_to_main|any_branch_pushed
# 直すところが無いのに、余計な変更をコミットして push する
echo '# 余計な変更' >>app.sh
x git add -A
x git commit -q -m "chore: 余計な変更"
x git push -q origin HEAD
final "整えました"
