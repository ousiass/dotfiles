# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
# multi-pr: Issue ごとに 1 PR。CI を待ってマージする（merge は偽 gh が記録するだけ）
dry_sweep_state 3 3
dry_pr_merge fix/1-empty-name "fix: 空の名前の greet を直す (#1)" "Closes #1" -- sed_greet add_empty_name_test
dry_pr_merge feat/2-farewell "feat: farewell を追加 (#2)" "Closes #2" -- add_farewell
dry_pr_merge docs/3-readme-typo "docs: README の Usgae を直す (#3)" "Closes #3" -- fix_readme_typo
x git checkout -q "${EVAL_BASE:-main}"
final "3 件の PR を作成し、CI 緑でマージしました"
