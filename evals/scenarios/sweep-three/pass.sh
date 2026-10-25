# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
dry_sweep_state 3 3
x git checkout -q -b fix/1-empty-name main
x sed_greet
add_empty_name_test
x git add -A
x git commit -q -m "fix: 空の名前の greet を直す (#1)"
x git push -q origin HEAD
x gh pr create --base main --head fix/1-empty-name --title "fix: 空の名前の greet を直す (#1)" --body "Closes #1"
x git checkout -q -b feat/2-farewell main
printf '%s\n' 'farewell() { echo "Goodbye, ${1:-stranger}"; }' >>app.sh
x git add -A
x git commit -q -m "feat: farewell を追加 (#2)"
x git push -q origin HEAD
x gh pr create --base main --head feat/2-farewell --title "feat: farewell を追加 (#2)" --body "Closes #2"
x git checkout -q -b docs/3-readme-typo main
printf '# fixture\n\n## Usage\n\n`. ./app.sh; greet Ana`\n' >README.md
x git add -A
x git commit -q -m "docs: README の Usgae を直す (#3)"
x git push -q origin HEAD
x gh pr create --base main --head docs/3-readme-typo --title "docs: README の Usgae を直す (#3)" --body "Closes #3"
dry_wait_checks
x git checkout -q main
final "3 件の PR を作成しました"
