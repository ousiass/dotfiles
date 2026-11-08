#!/usr/bin/env bash
# ousiass-design-guide / ousiass-design-check の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/ousiass_design_check_test.sh
#
# 守るもの:
#   1. .claude と .codex の「参照ファイル・テンプレート」が一致していること（SKILL.md だけは
#      frontmatter や対話ツールの記法が違うので比べない）。片方だけ更新するドリフトを防ぐ。
#   2. 基準の固定 SHA が guide（要約）と check（基準）で食い違わないこと。
#   3. check-criteria.md の「機械検出のレシピ」（T6〜T8 見出し / B スクロールバー）が、
#      `rg` 無しの環境（CI・macOS の既定）でも `grep -E` に読み替えて動き、
#      tests/fixtures/ousiass-design-check/ の見本から期待どおりの「候補」を拾うこと。
#      レシピは候補検出だけで、合否の判定ではない（判定は文脈・computed style・実動作で行う）。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
FX="$DOTFILES_DIR/tests/fixtures/ousiass-design-check"
CRITERIA="$DOTFILES_DIR/.claude/skills/ousiass-design-check/references/check-criteria.md"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

# --- 1. Claude / Codex の同期 ---
for rel in \
    ousiass-design-guide/references/brand-guide.md \
    ousiass-design-guide/templates/spec-section.md \
    ousiass-design-check/references/check-criteria.md \
    ousiass-design-check/templates/report.md; do
    if diff -q "$DOTFILES_DIR/.claude/skills/$rel" "$DOTFILES_DIR/.codex/skills/$rel" >/dev/null 2>&1; then
        ok "claude/codex 一致: $rel"
    else
        ng "claude/codex が不一致: $rel"
    fi
done

# --- 2. 固定 SHA の整合 ---
guide_sha=$(grep -m1 '^- 要約の取り込み時点' "$DOTFILES_DIR/.claude/skills/ousiass-design-guide/references/brand-guide.md" | grep -oE '`[0-9a-f]{7}`' | head -1 | tr -d '`')
check_sha=$(grep -m1 '固定 SHA は' "$CRITERIA" | grep -oE '`[0-9a-f]{7}`' | head -1 | tr -d '`')
if [[ -n "$guide_sha" && "$guide_sha" == "$check_sha" ]]; then
    ok "基準 SHA が guide と check で一致 ($guide_sha)"
else
    ng "基準 SHA が不一致または取得不可 (guide=$guide_sha / check=$check_sha)"
fi

# --- 3. 検出レシピ（rg → grep -E へ機械的に読み替えて実行）---
# check-criteria.md のコードブロックから、T6〜T8 / B の行だけを取り出す。
recipes=$(awk '/^# T6〜T8/{f=1} /^```$/{f=0} f && /^rg /' "$CRITERIA")
if [[ -z "$recipes" ]]; then
    ng "check-criteria.md から T6〜T8 / B のレシピを取り出せない"
fi

# 目印の断片 $1 を含むレシピを、$2（ファイルまたはディレクトリ）に対して grep -E で実行し、ヒット数を返す。
run_recipe() {
    local marker="$1" target="$2" line cmd
    line=$(printf '%s\n' "$recipes" | grep -F -- "$marker" | head -1)
    [[ -n "$line" ]] || { echo "NORECIPE"; return; }
    cmd=$(printf '%s\n' "$line" | sed -e 's/^rg -n -i /grep -rniE /' -e 's/^rg -n /grep -rnE /' -e "s|<dir>|\"$target\"|")
    eval "$cmd" 2>/dev/null | wc -l | tr -d ' '
}

check_hits() { # 名前 目印 対象 期待(>0 なら hit, 0 なら no-hit)
    local name="$1" marker="$2" target="$3" want="$4" got
    got=$(run_recipe "$marker" "$target")
    if [[ "$got" == "NORECIPE" ]]; then ng "$name (レシピが見つからない: $marker)"; return; fi
    if [[ "$want" == hit && "$got" -gt 0 ]] || [[ "$want" == nohit && "$got" -eq 0 ]]; then
        ok "$name (hit=$got)"
    else
        ng "$name (期待 $want / hit=$got)"
    fi
}

# B: バーを隠す指定は、隠している見本だけに出て、正本どおりの見本には出ない
check_hits "B6 隠蔽レシピ: 隠す見本を拾う"           'scrollbar-none' "$FX/finding-scrollbar-hidden.html"    hit
check_hits "B6 隠蔽レシピ: 正本どおりの見本は拾わない" 'scrollbar-none' "$FX/pass-scrollbar-canonical.html"   nohit
# B: スクロール領域・擬似要素・forced-colors の候補は、どの見本でも拾える（候補であって合否ではない）
check_hits "B 領域レシピ: 正本どおりの見本を拾う"     'overflow(-x|-y)?' "$FX/pass-scrollbar-canonical.html"  hit
check_hits "B 擬似要素レシピ: 正本どおりの見本を拾う" '::-webkit-scrollbar|scrollbar-(width' "$FX/pass-scrollbar-canonical.html" hit
check_hits "B 擬似要素レシピ: 優先関係の見本を拾う"   '::-webkit-scrollbar|scrollbar-(width' "$FX/finding-scrollbar-chromium-precedence.html" hit
# B: range スライダーのレシピは、スクロールバーの見本を range と取り違えない
check_hits "B5 range レシピ: スクロール見本は拾わない" 'type="range"' "$FX/pass-scrollbar-canonical.html"     nohit
# T6〜T8: 見出しタグは H1 の有無・開始レベルに関係なく拾える（候補。H1 なしを理由に落とさない）
check_hits "T 見出しレシピ: 小さい h1 を拾う"          '<h[1-6]' "$FX/pass-heading-small-h1.html"           hit
check_hits "T 見出しレシピ: H1 なし・h3 始まりを拾う"  '<h[1-6]' "$FX/pass-heading-no-h1-h3-start.html"    hit
check_hits "T 見出しレシピ: 要素セレクタの指定を拾う"  '(^|[[:space:],}>])h[1-6]' "$FX/finding-heading-tag-swapped.html" hit
check_hits "T 見出しレシピ: 役割クラスのみの指定は要素セレクタとして拾わない" '(^|[[:space:],}>])h[1-6]' "$FX/pass-heading-no-h1-h3-start.html" nohit

if [[ $fail -ne 0 ]]; then
    echo "ousiass design check のテストに失敗した" >&2
    exit 1
fi
echo "OK: ousiass design check tests"
