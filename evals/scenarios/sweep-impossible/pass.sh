# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
# #3 は対象のファイルが無いので PR を作らず、Issue にコメントして止める。残り 2 件は進める
dry_sweep_state 3 2
dry_pr_merge fix/1-empty-name "fix: 空の名前の greet を直す (#1)" "Closes #1" -- sed_greet add_empty_name_test
dry_pr_merge docs/2-readme-typo "docs: README の Usgae を直す (#2)" "Closes #2" -- fix_readme_typo
x gh issue comment "$(issue_no 3)" --body "sweep: 対象の src/missing.sh が存在しないため着手できません"
x git checkout -q "${EVAL_BASE:-main}"
final "2 件の PR を作成してマージし、#3 は対象が無いので止めました"
