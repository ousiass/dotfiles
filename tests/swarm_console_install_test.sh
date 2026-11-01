#!/usr/bin/env bash
# lib/tools/swarm_console.sh（install_swarm_console）の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/swarm_console_install_test.sh
#
# 実際のダウンロードも systemd の操作も行わない。HOME は一時ディレクトリに差し替え、PATH はスタブと
# 必要な実コマンドだけのディレクトリに絞る（curl / systemctl / loginctl / uname はスタブ。
# スタブが無いコマンドは「入っていない」扱いなので、動いている本物のサービスには届かない）。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

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

check_true() {
    local name="$1"
    shift
    if "$@"; then ok "$name"; else ng "$name"; fi
}

check_false() {
    local name="$1"
    shift
    if "$@"; then ng "$name"; else ok "$name"; fi
}

sha() {
    if command -v sha256sum >/dev/null 2>&1; then
        sha256sum "$1" | awk '{print $1}'
    else
        shasum -a 256 "$1" | awk '{print $1}'
    fi
}

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

home="$tmp/home"
release="$tmp/release"
stubs="$tmp/bin"
mkdir -p "$stubs" "$release"

export STUB_LOG="$tmp/calls.log"
export STUB_RELEASE="$release"
calls() { echo $(( $(grep -c -- "$1" "$STUB_LOG" || true) )); }

stub() {
    rm -f "$1"
    cat >"$1"
    chmod +x "$1"
}

# スクリプトとスタブが使う実コマンド（許可リスト）
for c in awk basename cat chmod dirname grep id ln mkdir mktemp mv readlink rm; do
    ln -sf "$(command -v "$c")" "$stubs/$c"
done
for c in sha256sum shasum; do
    if command -v "$c" >/dev/null 2>&1; then ln -sf "$(command -v "$c")" "$stubs/$c"; fi
done

stub "$stubs/uname" <<'EOF'
#!/bin/bash
case "$1" in
-m) echo "${STUB_UNAME_M:-x86_64}" ;;
*) echo "${STUB_UNAME_S:-Linux}" ;;
esac
EOF
# curl: URL の末尾のファイル名で $STUB_RELEASE から返す。STUB_CURL_FAIL に URL の末尾を入れるとそれだけ失敗する
stub "$stubs/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >>"$STUB_LOG"
out=""
url=""
while [ $# -gt 0 ]; do
    case "$1" in
    -o) out="$2"; shift ;;
    -*) ;;
    *) url="$1" ;;
    esac
    shift
done
if [ -n "${STUB_CURL_FAIL:-}" ] && [[ "$url" == *"$STUB_CURL_FAIL" ]]; then exit 22; fi
file="$STUB_RELEASE/$(basename "$url")"
[ -f "$file" ] || exit 22
if [ -n "$out" ]; then cat "$file" >"$out"; else cat "$file"; fi
EOF
# systemctl: 呼ばれた引数を記録する。STUB_SYSTEMCTL_FAIL に副コマンド（daemon-reload など）を入れるとそれだけ失敗する
make_systemctl_stub() {
    stub "$stubs/systemctl" <<'STUB'
#!/bin/bash
echo "systemctl $*" >>"$STUB_LOG"
[ "$2" = "${STUB_SYSTEMCTL_FAIL:-}" ] && exit 1
exit 0
STUB
}
make_systemctl_stub
# loginctl: STUB_LINGER=yes で linger 有効済み。STUB_LINGER_FAIL=1 で enable-linger が権限エラーになる
stub "$stubs/loginctl" <<'EOF'
#!/bin/bash
echo "loginctl $*" >>"$STUB_LOG"
case "$1" in
show-user) echo "Linger=${STUB_LINGER:-no}" ;;
--no-ask-password)
    [ -z "${STUB_LINGER_FAIL:-}" ]
    exit $?
    ;;
esac
exit 0
EOF

# 本番の install.sh と同じ set -euo pipefail で lib を読み込み、引数の関数を呼ぶ
driver="$tmp/driver.sh"
cat >"$driver" <<'EOF'
set -euo pipefail
export DOTFILES_DIR
CONFIG_DIR="$HOME/.config"
TIMESTAMP=test
OS="${TEST_OS:-linux}"
. "$DOTFILES_DIR/lib/load.sh"
"$@"
EOF

# run <関数名> [VAR=value ...] : 出力を $out、終了コードを $rc に入れる
run() {
    local fn="$1"
    shift
    out=$(env PATH="$stubs" HOME="$home" DOTFILES_DIR="$DOTFILES_DIR" "$@" "$BASH" "$driver" "$fn" 2>&1)
    rc=$?
}

# 新しいリリースを置く。reset_release <版> [バイナリの中身]
bin_path="$home/bin/swarm-console/swarm-console"
config_path="$home/.config/swarm-console/config.toml"
unit_path="$home/.config/systemd/user/swarm-console.service"

reset_release() {
    local tag="$1" body="${2:-binary-of-$1}"
    local asset="swarm-console_${tag}_linux_amd64"
    rm -f "$release"/*
    printf '%s' "$body" >"$release/$asset"
    {
        echo "$(sha "$release/$asset")  $asset"
        # 別 OS の行が混ざっていても linux_amd64 だけを選ぶこと
        echo "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef  swarm-console_${tag}_darwin_arm64"
    } >"$release/SHA256SUMS"
}

reset() {
    rm -rf "$home"
    mkdir -p "$home"
    : >"$STUB_LOG"
    reset_release v9.9.9
}

dir_entries() { echo $(( $(find "$1" -mindepth 1 -maxdepth 1 2>/dev/null | wc -l) )); }

# --- 実行権限つきの通常ファイルとして置く（初回） --------------------------------------------
reset
run install_swarm_console
check_eq    "初回: 成功する"                         0 "$rc"
check_true  "初回: バイナリを置く"                   test -f "$bin_path"
check_false "初回: シンボリックリンクにしない（自己更新の条件）" test -L "$bin_path"
check_true  "初回: 実行権限がある"                   test -x "$bin_path"
check_eq    "初回: 中身は取得したバイナリと同じ"     "binary-of-v9.9.9" "$(cat "$bin_path")"
check_eq    "初回: フォルダに一時ファイルを残さない" 1 "$(dir_entries "$home/bin/swarm-console")"
check_eq    "初回: 最新の SHA256SUMS を取る"         1 "$(calls 'releases/latest/download/SHA256SUMS')"
check_eq    "初回: SHA256SUMS の版（タグ）を指定して取る" 1 "$(calls 'releases/download/v9.9.9/swarm-console_v9.9.9_linux_amd64')"

# --- ユニットは dotfiles の systemd/ へのリンク。config.toml が無ければ起動せず案内だけ出す --------
check_true  "初回: ユニットを ~/.config/systemd/user に置く" test -L "$unit_path"
check_eq    "初回: ユニットは dotfiles の systemd/ へのリンク" "$DOTFILES_DIR/systemd/swarm-console.service" "$(readlink "$unit_path")"
check_eq    "初回: daemon-reload する"               1 "$(calls '^systemctl --user daemon-reload$')"
check_eq    "初回: enable する"                      1 "$(calls '^systemctl --user enable swarm-console.service$')"
check_eq    "初回: config.toml が無ければ起動しない" 0 "$(calls '--now\| start ')"
check_match "初回: 設定の手順を案内する（setup）"    "swarm-console setup" "$out"
check_match "初回: 設定の手順を案内する（token add）" "token add" "$out"
check_eq    "初回: linger を有効にする"              1 "$(calls '^loginctl --no-ask-password enable-linger ')"

# ユニットの ExecStart は、インストーラが置く場所のバイナリを指す（片方だけ動かすと動かなくなる）
exec_line="$(grep '^ExecStart=' "$DOTFILES_DIR/systemd/swarm-console.service")"
exec_bin="${exec_line#ExecStart=}"
exec_bin="${exec_bin%% *}"
check_eq    "ユニットの ExecStart はインストーラの置き場所" "$bin_path" "$home${exec_bin#%h}"

# --- 2 回目: 再ダウンロードも上書きもしない。自己更新で入れ替わった版を巻き戻さない -----------------
printf 'self-updated' >"$bin_path"
: >"$STUB_LOG"
run install_swarm_console
check_eq    "2 回目: 成功する"                       0 "$rc"
check_eq    "2 回目: ダウンロードしない"             0 "$(calls '^curl')"
check_eq    "2 回目: バイナリを書き換えない"         "self-updated" "$(cat "$bin_path")"
check_match "2 回目: 配置済みと出す"                 "既に配置済み" "$out"

# --- config.toml があれば起動する（enable --now）。動いているサービスは restart しない -----------
reset
mkdir -p "$(dirname "$config_path")"
: >"$config_path"
run install_swarm_console
check_eq    "config あり: 成功する"                  0 "$rc"
check_eq    "config あり: enable --now する"         1 "$(calls '^systemctl --user enable --now swarm-console.service$')"
check_eq    "config あり: restart しない"            0 "$(calls 'restart')"
check_eq    "config あり: 案内を出さない"            0 "$(printf '%s' "$out" | grep -c 'token add' || true)"

# --- 照合が合わなければ失敗にする。何も置かず、サービスにも触らない ---------------------------------
reset
printf '%s  swarm-console_v9.9.9_linux_amd64\n' "0000000000000000000000000000000000000000000000000000000000000000" >"$release/SHA256SUMS"
run install_swarm_console
check_eq    "sha256 不一致: 失敗する"                1 "$rc"
check_match "sha256 不一致: 理由を出す"              "一致しません" "$out"
check_false "sha256 不一致: バイナリを置かない"      test -e "$bin_path"
check_eq    "sha256 不一致: 一時ファイルを残さない"  0 "$(dir_entries "$home/bin/swarm-console")"
check_eq    "sha256 不一致: systemctl に触らない"    0 "$(calls '^systemctl\|^loginctl')"
check_false "sha256 不一致: ユニットを置かない"      test -e "$unit_path"

# --- SHA256SUMS に linux_amd64 の行が無い / ダウンロードに失敗する → 失敗（置かない） ----------------
reset
grep -v 'linux_amd64' "$release/SHA256SUMS" >"$tmp/sums" && cat "$tmp/sums" >"$release/SHA256SUMS"
run install_swarm_console
check_eq    "linux_amd64 の行が無い: 失敗する"      1 "$rc"
check_false "linux_amd64 の行が無い: バイナリを置かない" test -e "$bin_path"

reset
run install_swarm_console STUB_CURL_FAIL=swarm-console_v9.9.9_linux_amd64
check_eq    "バイナリのダウンロード失敗: 失敗する"   1 "$rc"
check_false "バイナリのダウンロード失敗: バイナリを置かない" test -e "$bin_path"
check_eq    "バイナリのダウンロード失敗: 一時ファイルを残さない" 0 "$(dir_entries "$home/bin/swarm-console")"

reset
run install_swarm_console STUB_CURL_FAIL=SHA256SUMS
check_eq    "SHA256SUMS の取得失敗: 失敗する"        1 "$rc"
check_false "SHA256SUMS の取得失敗: バイナリを置かない" test -e "$bin_path"

# --- 既にシンボリックリンクが置いてある: 触らず警告する（置き換えない） ----------------------------
reset
mkdir -p "$home/bin/swarm-console"
ln -s /nonexistent/swarm-console "$bin_path"
run install_swarm_console
check_eq    "リンクが置いてある: 成功する"           0 "$rc"
check_eq    "リンクが置いてある: リンクのまま"       "/nonexistent/swarm-console" "$(readlink "$bin_path")"
check_eq    "リンクが置いてある: ダウンロードしない" 0 "$(calls '^curl')"
check_match "リンクが置いてある: 警告する"           "シンボリックリンク" "$out"

# --- 既存の通常ファイルのユニット（手で置いたもの）は、既存のバックアップ規約でリンクに置き換える ---
reset
mkdir -p "$(dirname "$unit_path")" "$home/bin/swarm-console"
printf 'old-unit' >"$unit_path"
printf 'x' >"$bin_path"
run install_swarm_console
check_eq    "既存ユニットあり: 成功する"             0 "$rc"
check_true  "既存ユニットあり: リンクに置き換える"   test -L "$unit_path"
check_eq    "既存ユニットあり: 元の中身をバックアップ" "old-unit" "$(cat "$unit_path.bak.test" 2>/dev/null)"

# --- systemd の操作が失敗したら失敗にする ---------------------------------------------------
reset
run install_swarm_console STUB_SYSTEMCTL_FAIL=daemon-reload
check_eq    "daemon-reload 失敗: 失敗する"           1 "$rc"
reset
run install_swarm_console STUB_SYSTEMCTL_FAIL=enable
check_eq    "enable 失敗: 失敗する"                  1 "$rc"

# --- linger: 有効済みなら何もしない / 権限が無ければ警告だけで続行（パスワードは聞かない） ----------
reset
run install_swarm_console STUB_LINGER=yes
check_eq    "linger 有効済み: 成功する"              0 "$rc"
check_eq    "linger 有効済み: enable-linger しない"  0 "$(calls 'enable-linger')"
reset
run install_swarm_console STUB_LINGER_FAIL=1
check_eq    "linger 権限なし: 警告だけで成功する"    0 "$rc"
check_match "linger 権限なし: 警告を出す"            "enable-linger に失敗" "$out"

# --- systemctl が無い環境（macOS など）: バイナリは置き、サービス登録だけ飛ばす -------------------
reset
rm -f "$stubs/systemctl"
run install_swarm_console
check_eq    "systemctl なし: 成功する"               0 "$rc"
check_true  "systemctl なし: バイナリは置く"         test -f "$bin_path"
check_false "systemctl なし: ユニットを置かない"     test -e "$unit_path"
make_systemctl_stub

# --- 対象外（macOS / arm64）: 何もしない ----------------------------------------------------
reset
run install_swarm_console TEST_OS=mac STUB_UNAME_S=Darwin
check_eq    "macOS: 成功する"                        0 "$rc"
check_eq    "macOS: 何も呼ばない"                    0 "$(calls '^curl\|^systemctl\|^loginctl')"
check_false "macOS: バイナリを置かない"              test -e "$bin_path"
reset
run install_swarm_console STUB_UNAME_M=aarch64
check_eq    "arm64: 成功する"                        0 "$rc"
check_eq    "arm64: 何も呼ばない"                    0 "$(calls '^curl\|^systemctl\|^loginctl')"

# --- ./install.sh swarm_console（make swarm-console）が解決する関数名 -----------------------
out=$(env PATH="$stubs" HOME="$home" DOTFILES_DIR="$DOTFILES_DIR" "$BASH" "$driver" declare -F install_swarm_console 2>&1)
rc=$?
check_eq    "install.sh swarm_console: 関数が定義されている" 0 "$rc"

exit "$fail"
