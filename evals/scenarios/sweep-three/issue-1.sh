# shellcheck shell=bash
# Issue #1: 空の名前の greet は stranger
. ./app.sh
[ "$(greet '')" = "Hello, stranger" ] && [ "$(greet Ana)" = "Hello, Ana" ] && grep -rq stranger tests
