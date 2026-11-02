#!/usr/bin/env bash
# lib/tools/cloudflared.sh（install_cloudflared の apt 経路）の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/cloudflared_install_test.sh
#
# 実際のダウンロードも apt の操作も行わない。/etc/apt と /usr/share/keyrings には書かない:
# sudo スタブが絶対パスの引数を一時ディレクトリの下へ付け替える。PATH はスタブと必要な実コマンドだけに絞る
# （スタブが無いコマンドは「入っていない」扱い）。lsb_release は新しい Ubuntu の codename（resolute）を返すスタブ。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

# 失敗したときは run の出力（$tmp/out.log）も見せ、CI のログに原因を残す
check_eq() {
    local name="$1" want="$2" got="$3"
    if [[ "$want" == "$got" ]]; then
        ok "$name"
    else
        ng "$name (期待 $want / 実際 $got)"
        if [[ -f "$tmp/out.log" ]]; then sed 's/^/    | /' "$tmp/out.log"; fi
    fi
}

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

fakeroot="$tmp/root"
stubs="$tmp/bin"
mkdir -p "$stubs" "$fakeroot"
export STUB_LOG="$tmp/calls.log"
export FAKE_ROOT="$fakeroot"

stub() {
    rm -f "$1"
    cat >"$1"
    chmod +x "$1"
}

for c in cat tee; do
    ln -sf "$(command -v "$c")" "$stubs/$c"
done

# mkdir: 本番は GNU の `mkdir -p --mode=0755` を使う。macOS の BSD mkdir は --mode を解釈できず落ちるので、
# --mode=* を捨てて実物を呼ぶ（テストが見たいのは apt ソースの中身で、権限ビットではない）
real_mkdir="$(command -v mkdir)"
stub "$stubs/mkdir" <<EOF2
#!/bin/bash
args=()
for a in "\$@"; do
    case "\$a" in
    --mode=*) ;;
    *) args+=("\$a") ;;
    esac
done
exec "$real_mkdir" "\${args[@]}"
EOF2

# sudo: /etc/ と /usr/ で始まる引数を $FAKE_ROOT 配下に付け替えて実行する
stub "$stubs/sudo" <<'EOF2'
#!/bin/bash
args=()
for a in "$@"; do
    case "$a" in
    /etc/* | /usr/*) a="$FAKE_ROOT$a" ;;
    esac
    args+=("$a")
done
exec "${args[@]}"
EOF2
stub "$stubs/curl" <<'EOF2'
#!/bin/bash
echo "curl $*" >>"$STUB_LOG"
echo "fake-gpg-key"
EOF2
stub "$stubs/apt-get" <<'EOF2'
#!/bin/bash
echo "apt-get $*" >>"$STUB_LOG"
EOF2
stub "$stubs/lsb_release" <<'EOF2'
#!/bin/bash
echo resolute
EOF2

driver="$tmp/driver.sh"
cat >"$driver" <<'EOF2'
set -euo pipefail
export DOTFILES_DIR
CONFIG_DIR="$HOME/.config"
TIMESTAMP=test
OS=linux
. "$DOTFILES_DIR/lib/load.sh"
"$@"
EOF2

list="$fakeroot/etc/apt/sources.list.d/cloudflared.list"
old='deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared resolute main'
want='deb [signed-by=/usr/share/keyrings/cloudflare-main.gpg] https://pkg.cloudflare.com/cloudflared any main'

# run <関数名> : 終了コードを $rc に入れる。出力は $tmp/out.log に残し、check_eq が FAIL のときに見せる
run() {
    env PATH="$stubs" HOME="$tmp/home" DOTFILES_DIR="$DOTFILES_DIR" CLOUDFLARED_APT_LIST="$list" \
        "$BASH" "$driver" "$@" >"$tmp/out.log" 2>&1
    rc=$?
}

# reset [古い list の中身]: 一時ルートを作り直す。cloudflared は入っていない状態
reset() {
    rm -rf "$fakeroot" "$stubs/cloudflared"
    mkdir -p "$fakeroot/etc/apt/sources.list.d"
    : >"$STUB_LOG"
    if [[ $# -gt 0 ]]; then echo "$1" >"$list"; fi
}
installed() { stub "$stubs/cloudflared" <<<'#!/bin/bash'; }

# --- 初回: codename を埋め込まず any にする（Ubuntu 26.04 resolute で Release が無い不具合） ----
reset
run install_cloudflared
check_eq "初回: 成功する"                             0 "$rc"
check_eq "初回: apt ソースは any（codename 無し）"    "$want" "$(cat "$list" 2>/dev/null)"
check_eq "初回: apt-get install cloudflared まで進む" 1 "$(grep -c -- 'apt-get install -y cloudflared' "$STUB_LOG")"

# --- 古い codename が入った既存の cloudflared.list は any に上書きされる -------------------------
reset "$old"
run install_cloudflared
check_eq "既存 list: 成功する"                        0 "$rc"
check_eq "既存 list: 古い codename の行が any になる" "$want" "$(cat "$list" 2>/dev/null)"

# --- cloudflared が入っていても、残った古い list は any に直す（他の apt 操作が Release エラーで止まるため）----
reset "$old"
installed
run install_cloudflared
check_eq "導入済み install: 成功する"                 0 "$rc"
check_eq "導入済み install: 古い list を any にする"  "$want" "$(cat "$list" 2>/dev/null)"
check_eq "導入済み install: apt-get は呼ばない"       0 "$(grep -c 'apt-get' "$STUB_LOG")"

reset "$old"
installed
run update_cloudflared
check_eq "update: 成功する"                           0 "$rc"
check_eq "update: 古い list を any にしてから更新する" "$want" "$(cat "$list" 2>/dev/null)"
check_eq "update: apt-get install --only-upgrade まで進む" 1 "$(grep -c -- '--only-upgrade cloudflared' "$STUB_LOG")"

# --- list が無い（apt 以外で入れた）導入済みホストには、勝手に apt ソースを足さない ------------------
reset
installed
run install_cloudflared
check_eq "list 無し: 成功する"                        0 "$rc"
check_eq "list 無し: list を作らない"                 0 "$(test -e "$list" && echo 1 || echo 0)"

exit "$fail"
