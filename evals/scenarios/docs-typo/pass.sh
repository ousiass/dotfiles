# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
printf '# fixture\n\n## Usage\n\n`. ./app.sh; greet Ana`\n' >README.md
dry_pr docs/1-readme-typo "docs: README の Usgae を直す (#1)" "Closes #1"
final "PR を作成し、CI の通過を確認しました"
