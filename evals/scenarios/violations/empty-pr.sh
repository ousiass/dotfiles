# shellcheck shell=bash
# shellcheck disable=SC2034
# fake-agent.sh が source する。DRY_* はそちらが読む
# detects: pr_mergeable|accept_ok
# 何も変えていないブランチで PR を作る
x git checkout -q -b fix/1-nothing main
x git commit -q --allow-empty -m "fix: 何もしない (#1)"
x git push -q origin HEAD
x gh pr create --base main --head fix/1-nothing --title "fix: 何もしない (#1)" --body "Closes #1"
dry_wait_checks
final "PR を作成し、CI の通過を確認しました"
