#!/usr/bin/env bash
# シェルスクリプトの可搬性（macOS 標準の bash 3.2）の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/portability_test.sh
#
# 背景: macOS の bash 3.2 は、`$var` の直後に全角文字（全角括弧など）が続くと、その先頭バイトまで
# 変数名として読む。`set -u` の下で `echo "対象外です: ${OS}（...）"` を `$OS（...）` と書くと
# 「OS: unbound variable」で落ちる（#53、runner-host-setup.sh / runner-path-guard.sh / runner-tools-install.sh
# の 3 か所で再発した）。Linux の bash 5 では起きないため、実行テストでは固定できない。
# そこでソースを検査する。`${var}` で囲めば安全。
#
# あわせて、bash 3.2 に無い機能（mapfile / readarray / 連想配列 / ${var,,} ${var^^}）も検出する。
#
# BSD の grep には -P が無いので、LC_ALL=C の grep -E でバイト範囲（0x80 以上）を見る。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

# `$` + 識別子 + 非 ASCII バイト（${var} で囲んでいないもの）
HIGHBYTE_AFTER_VAR=$'\\$[A-Za-z_][A-Za-z0-9_]*[\x80-\xff]'
# bash 4 以降の機能
BASH4_ONLY='(^|[^A-Za-z_])(mapfile|readarray)[[:space:]]|(declare|local|typeset)[[:space:]]+-A[[:space:]]|\$\{[A-Za-z_][A-Za-z0-9_]*(,,|\^\^)'

# scan <pattern> <file...> : 一致した行を「ファイル:行番号:内容」で出す（コメント行は除く）
scan() {
    local pattern="$1"
    shift
    LC_ALL=C grep -nHE -- "$pattern" "$@" 2>/dev/null | LC_ALL=C grep -vE '^[^:]+:[0-9]+:[[:space:]]*#' || true
}

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

# --- 検査パターン自体が効いていること（効かないパターンで「0 件」になるのを防ぐ） ----------
printf 'echo "対象外です: $OS（Linux と macOS のみ）"\n' >"$tmp/bad.sh"
printf 'echo "対象外です: ${OS}（Linux と macOS のみ）"\necho "$OS"\necho "$x "\n' >"$tmp/good.sh"
[[ -n "$(scan "$HIGHBYTE_AFTER_VAR" "$tmp/bad.sh")" ]] && ok "検査: \$var の直後の全角文字を検出する" || ng "検査: \$var の直後の全角文字を検出できない"
[[ -z "$(scan "$HIGHBYTE_AFTER_VAR" "$tmp/good.sh")" ]] && ok "検査: \${var} で囲んだものは検出しない" || ng "検査: \${var} で囲んだものまで検出している"
printf 'mapfile -t a < <(ls)\n' >"$tmp/bash4.sh"
[[ -n "$(scan "$BASH4_ONLY" "$tmp/bash4.sh")" ]] && ok "検査: mapfile を検出する" || ng "検査: mapfile を検出できない"
printf '# mapfile は bash 4 以降\n' >"$tmp/comment.sh"
[[ -z "$(scan "$BASH4_ONLY" "$tmp/comment.sh")" ]] && ok "検査: コメント内の言及は検出しない" || ng "検査: コメント内の言及まで検出している"

# --- 本番: git 管理下の全 *.sh（このテスト自身は検査パターンを含むので除く） ------------------
files=()
while IFS= read -r f; do
    [[ "$f" == tests/portability_test.sh ]] && continue
    files+=("$DOTFILES_DIR/$f")
done < <(git -C "$DOTFILES_DIR" ls-files '*.sh')

if [[ "${#files[@]}" -eq 0 ]]; then
    ng "検査対象の *.sh が見つからない（git ls-files が空）"
else
    ok "検査対象: ${#files[@]} ファイル"
fi

hits="$(scan "$HIGHBYTE_AFTER_VAR" "${files[@]}")"
if [[ -z "$hits" ]]; then ok "\$var の直後に全角文字が無い（bash 3.2 + set -u で落ちない）"; else ng "\$var の直後に全角文字がある。\${var} で囲むこと:
$hits"; fi

hits="$(scan "$BASH4_ONLY" "${files[@]}")"
if [[ -z "$hits" ]]; then ok "bash 4 以降の機能（mapfile / readarray / 連想配列 / \${var,,}）を使っていない"; else ng "bash 3.2 に無い機能がある:
$hits"; fi

exit "$fail"
