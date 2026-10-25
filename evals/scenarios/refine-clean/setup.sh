# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
git checkout -q -b feat/wip
printf '%s\n' 'farewell() { echo "Goodbye, $1"; }' >>app.sh
echo 't "farewell: 名前あり" "Goodbye, Ana" "$(farewell Ana)"' >tests/20_farewell.sh
