# shellcheck shell=bash
# fake-agent.sh / fixture.sh が source する断片（evals/lib 参照）
cat >lang.sh <<'X'
lang_greet() {
    case "${APP_LANG:-en}" in
    en) echo "Hello, $1" ;;
    ja) echo "こんにちは、$1" ;;
    *)
        echo "unknown lang: ${APP_LANG}" >&2
        echo "Hello, $1"
        ;;
    esac
}
X
cat >app.sh <<'X'
#!/usr/bin/env bash
# eval 用の題材（小さな bash ライブラリ）
. "$(dirname "${BASH_SOURCE[0]}")/lang.sh"
greet() { lang_greet "$1"; }
shout() { echo "$1" | tr a-z A-Z; }
X
cat >tests/20_lang.sh <<'X'
t "lang: 既定は en" "Hello, Ana" "$(greet Ana)"
t "lang: ja" "こんにちは、Ana" "$(APP_LANG=ja greet Ana)"
t "lang: 未対応の言語は en の文言" "Hello, Ana" "$(APP_LANG=fr greet Ana 2>/dev/null)"
t "lang: 未対応の言語は標準エラーに出す" "unknown lang: fr" "$(APP_LANG=fr greet Ana 2>&1 >/dev/null)"
X
printf '\n`APP_LANG=ja greet Ana` で言語を選べる（en・ja）。\n' >>README.md
dry_pr feat/1-lang "feat: greet の言語を切り替える (#1)" "Closes #1"
final "PR を作成し、CI の通過を確認しました"
