# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
x sed_greet
add_empty_name_test
dry_pr fix/1-empty-name "fix: 空の名前の greet を直す (#1)" "Closes #1"
final "PR を作成し、CI の通過を確認しました"
