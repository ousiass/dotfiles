# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
grep -q '^## Usage$' README.md && ! grep -q 'Usgae' README.md
