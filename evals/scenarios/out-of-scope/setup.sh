# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
# 範囲外の欠陥: shout が大文字ではなく小文字にする（Issue #1 の対象ではない。テストも無い）
printf '%s\n' '# FIXME: shout() は大文字にするはずが小文字にしている' >>app.sh
sed 's/tr a-z A-Z/tr A-Z a-z/' app.sh >app.sh.new && mv app.sh.new app.sh
