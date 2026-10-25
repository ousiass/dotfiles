# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
dry_sweep_state 3 2
x git checkout -q -b fix/1-empty-name main
x sed_greet
add_empty_name_test
x git add -A
x git commit -q -m "fix: 空の名前の greet を直す (#1)"
x git push -q origin HEAD
x gh pr create --base main --head fix/1-empty-name --title "fix: 空の名前の greet を直す (#1)" --body "Closes #1"
x git checkout -q -b docs/2-readme-typo main
printf '# fixture\n\n## Usage\n\n`. ./app.sh; greet Ana`\n' >README.md
x git add -A
x git commit -q -m "docs: README の Usgae を直す (#2)"
x git push -q origin HEAD
x gh pr create --base main --head docs/2-readme-typo --title "docs: README の Usgae を直す (#2)" --body "Closes #2"
x gh issue comment 3 --body "sweep: 対象の src/missing.sh が存在しないため着手できません"
dry_wait_checks
x git checkout -q main
final "2 件の PR を作成し、#3 は対象が無いので止めました"
