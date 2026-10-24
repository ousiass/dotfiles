#!/usr/bin/env bash
# runner-tools-install.sh の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/runner_tools_install_test.sh
#
# 実際のインストールは行わない。brew / apt-get / sudo / fnm / curl などは、PATH を
# スタブだけのディレクトリに絞って差し替える（スタブが無いコマンドは「入っていない」扱いになる）。
# curl のスタブは、呼ばれたらテストを失敗させる（公式インストーラのダウンロードを防ぐ）。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$DOTFILES_DIR/runner-tools-install.sh"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

check_eq() {
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then ok "$name"; else ng "$name (期待 $want / 実際 $got)"; fi
}

check_match() {
    local name="$1" pattern="$2" text="$3"
    if [[ "$text" == *"$pattern"* ]]; then ok "$name"; else ng "$name ('$pattern' が無い: $text)"; fi
}

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

export STUB_LOG="$tmp/calls.log"
calls() { echo $(( $(grep -c "$1" "$STUB_LOG" || true) )); }

# 入っている扱いのコマンド（brew formula 名・コマンド名）の一覧ファイル。1 行 1 つ。
export STUB_INSTALLED="$tmp/installed"

stubs="$tmp/bin"
mkdir -p "$stubs" "$tmp/home"

stub() { cat >"$1"
    chmod +x "$1"; }

# スクリプトとスタブが使う外部コマンドのうち、スタブにしないもの（dirname / grep）は実物を使う。
ln -s "$(command -v dirname)" "$stubs/dirname"
ln -s "$(command -v grep)" "$stubs/grep"

stub "$stubs/uname" <<'EOF'
#!/bin/bash
echo "${STUB_UNAME_S:-Darwin}"
EOF
stub "$stubs/id" <<'EOF'
#!/bin/bash
[ "$1" = -u ] && echo "${STUB_ID_U:-501}" || echo staff
EOF
stub "$stubs/xcode-select" <<'EOF'
#!/bin/bash
[ -z "${STUB_NO_CLT:-}" ] && echo /Library/Developer/CommandLineTools
EOF
stub "$stubs/security" <<'EOF'
#!/bin/bash
echo "     ${STUB_IDENTITIES:-0} valid identities found"
EOF
# brew list / install。install したものは STUB_INSTALLED に追記する（2 回目以降は入っている扱い）。
stub "$stubs/brew" <<'EOF'
#!/bin/bash
echo "brew $*" >>"$STUB_LOG"
case "$1" in
list) grep -qxF "$3" "$STUB_INSTALLED" ;;
install)
    case " ${STUB_BREW_INSTALL_FAIL:-} " in *" $2 "*) exit 1 ;; esac
    echo "$2" >>"$STUB_INSTALLED"
    ;;
esac
EOF
# fnm は「brew で入れたら存在する」扱い。brew 側の STUB_INSTALLED に fnm があるときだけ動く。
stub "$stubs/fnm" <<'EOF'
#!/bin/bash
echo "fnm $*" >>"$STUB_LOG"
if [ "$1" = exec ]; then
    [ -f "$STUB_NODE_DEFAULT" ]
    exit $?
fi
if [ "$1" = default ]; then
    : >"$STUB_NODE_DEFAULT"
fi
exit 0
EOF
export STUB_NODE_DEFAULT="$tmp/node-default"
stub "$stubs/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >>"$STUB_LOG"
echo "LEAK: ネットワークからダウンロードしようとした" >>"$STUB_LOG"
exit 99
EOF

all_formulae="colima docker docker-buildx fnm gh jq shellcheck fish"

# run [VAR=value ...] : 出力を $out、終了コードを $rc に入れる（PATH はスタブだけ）
run() {
    out=$(env PATH="$stubs" HOME="$tmp/home" XCODE_APP="$tmp/Xcode.app" "$@" "$BASH" "$SCRIPT" 2>&1)
    rc=$?
}

reset() { # reset [installed formula ...]
    : >"$STUB_LOG"
    : >"$STUB_INSTALLED"
    rm -f "$STUB_NODE_DEFAULT"
    local f
    for f in "$@"; do echo "$f" >>"$STUB_INSTALLED"; done
}

# --- root では動かさない（brew は root を拒否し、fnm / Node はホームに入るため） -------------
reset
run STUB_ID_U=0
check_eq    "root: 失敗で止まる"                 1 "$rc"
check_match "root: 理由を出す"                   "root では実行できません" "$out"
check_eq    "root: 何も実行しない"               0 "$(calls '^brew\|^fnm')"

# --- macOS: 足りないものだけを入れる ---------------------------------------------------
reset docker jq shellcheck
: >"$STUB_NODE_DEFAULT"
run
check_eq    "macOS 一部不足: 成功する"            0 "$rc"
for f in colima docker-buildx fnm gh fish; do
    check_eq "macOS 一部不足: $f を入れる"        1 "$(calls "^brew install $f\$")"
done
for f in docker jq shellcheck; do
    check_eq "macOS 一部不足: 入っている $f は飛ばす" 0 "$(calls "^brew install $f\$")"
done
check_eq    "macOS 一部不足: Node の default は設定済みなので入れない" 0 "$(calls '^fnm install')"

# --- 2 回続けて回しても同じ（2 回目は何も入れない） ----------------------------------------
: >"$STUB_LOG"
run
check_eq    "2 回目: 成功する"                    0 "$rc"
check_eq    "2 回目: 何も brew install しない"    0 "$(calls '^brew install')"
check_match "2 回目: そろっていると表示する"      "runner に要るツールはそろっています" "$out"

# --- macOS: すべて入っていれば何もしない --------------------------------------------------
reset $all_formulae
: >"$STUB_NODE_DEFAULT"
run
check_eq    "macOS 全部あり: 成功する"            0 "$rc"
check_eq    "macOS 全部あり: 何も入れない"        0 "$(calls '^brew install\|^fnm install')"

# --- Node の default が無ければ fnm で LTS を入れて default にする -----------------------------
reset $all_formulae
run
check_eq    "Node 未設定: 成功する"               0 "$rc"
check_eq    "Node 未設定: fnm install --lts"      1 "$(calls '^fnm install --lts$')"
check_eq    "Node 未設定: fnm default lts-latest" 1 "$(calls '^fnm default lts-latest$')"
: >"$STUB_LOG"
run
check_eq    "Node 設定後の 2 回目: 入れ直さない"  0 "$(calls '^fnm install')"

# --- 入れるのに失敗したものは最後に報告して失敗で終わる（残りは試す） -------------------------
reset docker
: >"$STUB_NODE_DEFAULT"
run STUB_BREW_INSTALL_FAIL="colima gh"
check_eq    "install 失敗: 失敗で終わる"          1 "$rc"
check_match "install 失敗: 失敗したものを報告する" "インストールできなかったもの: colima gh" "$out"
check_eq    "install 失敗: 残りは試す（jq）"      1 "$(calls '^brew install jq$')"

# --- Homebrew が無ければ自動で入れず、案内して止まる -------------------------------------------
nobrew="$tmp/bin-nobrew"
mkdir -p "$nobrew"
for f in "$stubs"/*; do [ "$(basename "$f")" = brew ] || ln -s "$f" "$nobrew/$(basename "$f")"; done
reset
out=$(env PATH="$nobrew" HOME="$tmp/home" XCODE_APP="$tmp/Xcode.app" "$BASH" "$SCRIPT" 2>&1)
rc=$?
check_eq    "Homebrew 無し: 失敗で止まる"         1 "$rc"
check_match "Homebrew 無し: 入れ方を案内する"     "https://brew.sh" "$out"
check_match "Homebrew 無し: 自動では入れないと分かる" "自動で入れません" "$out"
check_eq    "Homebrew 無し: curl を呼ばない"      0 "$(calls '^curl')"

# --- Xcode コマンドラインツールが無ければ案内して止まる -----------------------------------------
reset
run STUB_NO_CLT=1
check_eq    "CLT 無し: 失敗で止まる"              1 "$rc"
check_match "CLT 無し: 入れ方を案内する"          "xcode-select --install" "$out"
check_eq    "CLT 無し: brew を呼ばない"           0 "$(calls '^brew')"

# --- Xcode 本体・署名証明書は入れず、有無を表示するだけ ----------------------------------------
reset $all_formulae
: >"$STUB_NODE_DEFAULT"
run
check_match "Xcode 本体無し: 無いと表示する"      "Xcode 本体が入っていません" "$out"
check_match "署名証明書無し: 無いと表示する"      "コード署名の証明書が見つかりません" "$out"
check_eq    "Xcode / 証明書が無くても成功する"     0 "$rc"
check_eq    "Xcode / 証明書は入れようとしない"     0 "$(calls '^brew install\|^curl')"
mkdir -p "$tmp/Xcode.app"
run STUB_IDENTITIES=2
check_match "Xcode 本体あり: あると表示する"      "Xcode 本体: あり" "$out"
check_match "署名証明書あり: あると表示する"      "コード署名の証明書: あり" "$out"

# --- Linux: 足りない apt パッケージだけを入れる（fnm / gh は入っている扱いで curl を呼ばせない） ---
# Linux は apt-get と sudo をスタブにする。jq / fnm / gh / node default は入っている扱い。
reset
: >"$STUB_NODE_DEFAULT"
lbin="$tmp/bin-linux"
mkdir -p "$lbin"
for f in "$stubs"/*; do ln -s "$f" "$lbin/$(basename "$f")"; done
stub "$lbin/apt-get" <<'EOF'
#!/bin/bash
echo "apt-get $*" >>"$STUB_LOG"
EOF
stub "$lbin/sudo" <<'EOF'
#!/bin/bash
exec "$@"
EOF
stub "$lbin/jq" <<'EOF'
#!/bin/bash
EOF
stub "$lbin/gh" <<'EOF'
#!/bin/bash
EOF
out=$(env PATH="$lbin" STUB_UNAME_S=Linux HOME="$tmp/home" "$BASH" "$SCRIPT" 2>&1)
rc=$?
check_eq    "Linux: 成功する"                     0 "$rc"
check_eq    "Linux: 足りない shellcheck / fish だけ入れる" 1 "$(calls '^apt-get install -y shellcheck fish$')"
check_eq    "Linux: 入っている jq は入れない"      0 "$(calls '^apt-get install -y .*jq')"
check_eq    "Linux: brew を呼ばない"              0 "$(calls '^brew')"
check_eq    "Linux: ダウンロードしない"           0 "$(calls '^curl')"
: >"$STUB_LOG"
stub "$lbin/shellcheck" <<'EOF'
#!/bin/bash
EOF
stub "$lbin/fish" <<'EOF'
#!/bin/bash
EOF
out=$(env PATH="$lbin" STUB_UNAME_S=Linux HOME="$tmp/home" "$BASH" "$SCRIPT" 2>&1)
rc=$?
check_eq    "Linux 2 回目: 成功する"              0 "$rc"
check_eq    "Linux 2 回目: 何も入れない"          0 "$(calls '^apt-get install')"

exit "$fail"
