# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
x sed_greet
add_empty_name_test
if [ -z "${DRY_SPINOFF_IN_BODY:-}" ]; then
    x gh issue create --title "bug: shout() が小文字にしている" --label spinoff --body "#1 の作業中に見つけた範囲外の欠陥。"
    dry_pr fix/1-empty-name "fix: 空の名前の greet を直す (#1)" "Closes #1"
else
    dry_pr fix/1-empty-name "fix: 空の名前の greet を直す (#1)" "Closes #1

## スピンオフ
- shout() が小文字にしている（別 Issue にしていない）"
fi
final "PR を作成し、範囲外の欠陥はスピンオフにしました"
