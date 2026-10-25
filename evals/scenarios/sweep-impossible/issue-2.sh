# shellcheck shell=bash
# Issue #2: README の見出しの綴り
grep -q '^## Usage$' README.md && ! grep -q 'Usgae' README.md
