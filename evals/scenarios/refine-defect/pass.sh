# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
sed 's/Goodbye,\$1/Goodbye, $1/' app.sh >app.sh.new && mv app.sh.new app.sh
x git add -A
x git commit -q -m "fix: farewell の区切りの空白を直す"
x git push -q origin HEAD
final "指摘を直して push しました"
