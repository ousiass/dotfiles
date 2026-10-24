#!/usr/bin/env bash
# runner-path-guard.sh の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/runner_path_guard_test.sh
#
# 背景: runner の runsvc.sh は .path があれば PATH を丸ごとそれで上書きする。
# fish ログイン中に config.sh / svc.sh install を実行すると fnm の一時パス
# （fnm_multishells）が .path に記録され、再起動で node が見えなくなった（#36 / #37）。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GUARD="$DOTFILES_DIR/runner-path-guard.sh"
# shellcheck source=../runner-path-guard.sh
. "$GUARD"

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

check_no_match() {
    local name="$1" pattern="$2" text="$3"
    if [[ "$text" != *"$pattern"* ]]; then ok "$name"; else ng "$name ('$pattern' がある: $text)"; fi
}

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

# ホームごとに runner dir を作り、node / npx を置くかどうかを選ぶ。
# new_runner <name> <with_node: yes|no> → $home / $runner_dir を設定する
new_runner() {
    home="$tmp/$1/home"
    runner_dir="$tmp/$1/actions-runner"
    mkdir -p "$home/.local/share/fnm/aliases/default/bin" "$runner_dir"
    if [[ "$2" == yes ]]; then
        printf '#!/bin/sh\n' >"$home/.local/share/fnm/aliases/default/bin/node"
        cp "$home/.local/share/fnm/aliases/default/bin/node" "$home/.local/share/fnm/aliases/default/bin/npx"
        chmod +x "$home/.local/share/fnm/aliases/default/bin/node" "$home/.local/share/fnm/aliases/default/bin/npx"
    fi
}

count_backups() { find "$runner_dir" -maxdepth 1 -name '.path.bak-*' | wc -l; }

# --- fnm_multishells を含む .path は安定 PATH へ直り、バックアップと log が残る ----
new_runner multishell yes
stale="/run/user/1000/fnm_multishells/1234_5678/bin:/usr/bin:/bin"
echo "$stale" >"$runner_dir/.path"
out=$("$GUARD" "$runner_dir" "$home" 2>&1); rc=$?
check_eq    "fnm_multishells: 起動は止めない (exit 0)"  0 "$rc"
check_eq    "fnm_multishells: 安定 PATH に書き直す"      "$(runner_stable_path "$home")" "$(<"$runner_dir/.path")"
check_eq    "fnm_multishells: バックアップが 1 つ残る"   1 "$(count_backups)"
check_eq    "fnm_multishells: バックアップは元の内容"    "$stale" "$(cat "$runner_dir"/.path.bak-*)"
check_match "fnm_multishells: 修復を出力する"            "path-guard: $runner_dir/.path を安定 PATH に修復する" "$out"

# --- aliases/default/bin を含まない .path は直る -----------------------------
new_runner no-alias yes
echo "/usr/local/bin:/usr/bin:/bin" >"$runner_dir/.path"
"$GUARD" "$runner_dir" "$home" >/dev/null 2>&1
check_eq "aliases/default/bin 無し: 安定 PATH に書き直す" "$(runner_stable_path "$home")" "$(<"$runner_dir/.path")"

# --- .path が無ければ作る（バックアップは不要） ------------------------------
new_runner no-file yes
"$GUARD" "$runner_dir" "$home" >/dev/null 2>&1
check_eq "ファイル無し: 安定 PATH で作る"         "$(runner_stable_path "$home")" "$(<"$runner_dir/.path")"
check_eq "ファイル無し: バックアップは作らない"   0 "$(count_backups)"

# --- 正常な .path は書き換えない（安定 PATH と同一でなくてもよい） ---------------
new_runner healthy yes
healthy="$home/.local/share/fnm/aliases/default/bin:/usr/bin:/bin"
echo "$healthy" >"$runner_dir/.path"
before=$(stat -c '%i %Y' "$runner_dir/.path")
out=$("$GUARD" "$runner_dir" "$home" 2>&1); rc=$?
check_eq "正常: exit 0"                         0 "$rc"
check_eq "正常: 内容を書き換えない"              "$healthy" "$(<"$runner_dir/.path")"
check_eq "正常: ファイルに触らない"              "$before" "$(stat -c '%i %Y' "$runner_dir/.path")"
check_eq "正常: バックアップを作らない"          0 "$(count_backups)"
check_eq "正常: 何も出力しない"                  "" "$out"

# --- node が無いとき: 直した上でエラーを出すが、起動は止めない -------------------
new_runner nonode no
echo "$stale" >"$runner_dir/.path"
out=$("$GUARD" "$runner_dir" "$home" 2>&1); rc=$?
check_eq    "node 無し: exit 0（起動を止めない）" 0 "$rc"
check_eq    "node 無し: 安定 PATH に書き直す"      "$(runner_stable_path "$home")" "$(<"$runner_dir/.path")"
check_match "node 無し: NG を出す"                 "NG: 安定 PATH でも node / npx が見えません" "$out"

# --- 既に安定 PATH で node が無いとき: 書き直さず（バックアップも増やさず）NG だけ出す ----
out=$("$GUARD" "$runner_dir" "$home" 2>&1); rc=$?
check_eq    "安定 PATH + node 無し: exit 0"         0 "$rc"
check_eq    "安定 PATH + node 無し: バックアップ増えない" 1 "$(count_backups)"
check_match "安定 PATH + node 無し: NG を出す"      "NG: 安定 PATH でも node / npx が見えません" "$out"

# --- 引数不足でも exit 0（ExecStartPre が runner の起動を止めない） ---------------
"$GUARD" >/dev/null 2>&1
check_eq "引数不足: exit 0" 0 "$?"

# --- 安定 PATH は OS（uname -s）で分かれる -----------------------------------------
# uname を関数で差し替えて、macOS と Linux の定義を同じホストで確かめる。
linux_path=$(uname() { echo Linux; }; runner_stable_path /h)
mac_path=$(uname() { echo Darwin; }; runner_stable_path /h)
check_match    "macOS の安定 PATH: Application Support の fnm の aliases/default/bin が先頭" ":${mac_path%%:*}:" ":/h/Library/Application Support/fnm/aliases/default/bin:"
check_match    "macOS の安定 PATH: ~/.local/share/fnm の aliases/default/bin も含む" ":/h/.local/share/fnm/aliases/default/bin:" ":$mac_path:"
check_match    "macOS の安定 PATH: Homebrew (Apple Silicon) を含む"   ":/opt/homebrew/bin:" ":$mac_path:"
check_match    "macOS の安定 PATH: /opt/homebrew/sbin を含む"         ":/opt/homebrew/sbin:" ":$mac_path:"
check_match    "macOS の安定 PATH: 標準の /usr/bin /bin を含む"       ":/usr/bin:/bin:" ":$mac_path:"
for linux_only in /snap/bin /opt/nvim/bin /usr/games /usr/local/games /usr/local/sbin; do
    check_no_match "macOS の安定 PATH: Linux 専用の $linux_only を含まない" ":$linux_only:" ":$mac_path:"
done
check_match    "Linux の安定 PATH: /snap/bin を含む（従来どおり）"    ":/snap/bin:" ":$linux_path:"
check_no_match "Linux の安定 PATH: /opt/homebrew を含まない"          "/opt/homebrew" "$linux_path"

# macOS でも fnm_multishells を含む .path は macOS の安定 PATH へ直る
new_runner mac-multishell yes
echo "$stale" >"$runner_dir/.path"
( uname() { echo Darwin; }; runner_repair_path_file "$runner_dir/.path" "$home" >/dev/null 2>&1 )
check_eq "macOS: 安定 PATH に書き直す" "$(uname() { echo Darwin; }; runner_stable_path "$home")" "$(<"$runner_dir/.path")"

# macOS の fnm は公式インストーラの既定で ~/Library/Application Support/fnm に入る。
# aliases/default/bin がそちらにあるだけの .path も正常とみなし、どちらにも無ければ直す。
new_runner mac-appsupport no
app_bin="$home/Library/Application Support/fnm/aliases/default/bin"
mkdir -p "$app_bin"
printf '#!/bin/sh\n' >"$app_bin/node"
cp "$app_bin/node" "$app_bin/npx"
chmod +x "$app_bin/node" "$app_bin/npx"
app_healthy="$app_bin:/usr/bin:/bin"
echo "$app_healthy" >"$runner_dir/.path"
out=$(uname() { echo Darwin; }; runner_path_guard_main "$runner_dir" "$home" 2>&1)
check_eq "macOS: Application Support の fnm を指す .path は正常（書き換えない）" "$app_healthy" "$(<"$runner_dir/.path")"
check_eq "macOS: Application Support の fnm: 何も出力しない" "" "$out"
echo "/usr/bin:/bin" >"$runner_dir/.path"
( uname() { echo Darwin; }; runner_path_guard_main "$runner_dir" "$home" >/dev/null 2>&1 )
check_eq "macOS: どちらの fnm も無い .path は安定 PATH へ直る" "$(uname() { echo Darwin; }; runner_stable_path "$home")" "$(<"$runner_dir/.path")"
check_match "macOS: 安定 PATH は Application Support の fnm を含む" ":$app_bin:" ":$(<"$runner_dir/.path"):"
# Linux では Application Support を見ない（従来どおり ~/.local/share/fnm のみ）
new_runner linux-appsupport no
mkdir -p "$home/Library/Application Support/fnm/aliases/default/bin"
cp "$app_bin/node" "$home/Library/Application Support/fnm/aliases/default/bin/node" 2>/dev/null || true
echo "$home/Library/Application Support/fnm/aliases/default/bin:/usr/bin:/bin" >"$runner_dir/.path"
out=$(uname() { echo Linux; }; runner_path_file_problem "$runner_dir/.path" "$home")
check_match "Linux: Application Support の fnm は認めない" "$home/.local/share/fnm/aliases/default/bin を含まない" "$out"

# Linux の安定 PATH は変更前の文字列と完全一致（origin/main の runner_stable_path から転記）
check_eq "Linux の安定 PATH: 従来と完全一致" "/h/.local/share/fnm/aliases/default/bin:/opt/nvim/bin:/usr/local/go/bin:/h/go/bin:/h/.cargo/bin:/h/.bun/bin:/h/.local/bin:/h/.local/share/fnm:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/usr/games:/usr/local/games:/snap/bin" "$linux_path"

exit "$fail"
