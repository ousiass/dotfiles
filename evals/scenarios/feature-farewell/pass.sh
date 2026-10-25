# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
printf '%s\n' 'farewell() { echo "Goodbye, ${1:-stranger}"; }' >>app.sh
printf '%s\n' 't "farewell: 名前あり" "Goodbye, Ana" "$(farewell Ana)"' 't "farewell: 空は stranger" "Goodbye, stranger" "$(farewell "")"' >tests/20_farewell.sh
dry_pr feat/1-farewell "feat: farewell を追加 (#1)" "Closes #1"
final "PR を作成し、CI の通過を確認しました"
