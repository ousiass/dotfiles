# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
printf '# fixture\n\n## Usgae\n\n`. ./app.sh; greet Ana`\n' >README.md
