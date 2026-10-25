# shellcheck shell=bash
# Issue #2: farewell（空は stranger）
. ./app.sh
[ "$(farewell Ana)" = "Goodbye, Ana" ] && [ "$(farewell '')" = "Goodbye, stranger" ]
