#!/usr/bin/env bash
# runner-host-setup.sh の macOS（Apple Silicon / launchd / colima）分岐の回帰テスト。
# フレームワークは使わず bash だけで完結させる。
#
#   ./tests/runner_host_setup_test.sh
#
# Linux 上で動かすため、uname / id / dscl / sudo / brew / docker / launchctl などを PATH 先頭の
# スタブに差し替える。スタブが見るのは「呼ばれ方」だけで、macOS 実機の挙動（launchd の読み込み、
# colima の起動、brew services）の代わりにはならない。実機確認が必要な項目は PR 本文に挙げる。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SETUP="$DOTFILES_DIR/runner-host-setup.sh"
# shellcheck source=../runner-path-guard.sh
. "$DOTFILES_DIR/runner-path-guard.sh"
# 期待値（macOS の安定 PATH）をこのシェルでも macOS として計算する。子プロセスには PATH 先頭の uname スタブが効く。
uname() { echo Darwin; }

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

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

stubs="$tmp/bin"
home="$tmp/Users/ci"
runner_dir="$home/actions-runner"
fnm_bin="$home/.local/share/fnm/aliases/default/bin"
export STUB_LOG="$tmp/calls.log"
export STUB_HOME="$home"
export STUB_LAUNCHD_LIST="$tmp/launchd.list"

mkdir -p "$stubs" "$home/.local/bin" "$fnm_bin" "$runner_dir"

stub() { # stub <path> : 標準入力の内容を実行可能ファイルとして書く
    cat >"$1"
    chmod +x "$1"
}

# --- PATH 先頭に置くスタブ（root・macOS コマンドの代役） -----------------------------
stub "$stubs/uname" <<'EOF'
#!/bin/bash
case "$1" in
-s) echo "${STUB_UNAME_S:-Darwin}" ;;
-m) echo "${STUB_UNAME_M:-arm64}" ;;
*) echo "${STUB_UNAME_S:-Darwin}" ;;
esac
EOF
stub "$stubs/id" <<'EOF'
#!/bin/bash
case "$1" in
-u) echo 0 ;;
*) echo staff ;;
esac
EOF
stub "$stubs/dscl" <<'EOF'
#!/bin/bash
# dscl . -read /Users/<user> NFSHomeDirectory
if [ "$3" = "/Users/ci" ]; then
    echo "NFSHomeDirectory: $STUB_HOME"
else
    echo "<dscl_cmd> DS Error: -14136 (eDSRecordNotFound)" >&2
    exit 56
fi
EOF
# sudo -u <user> -H <cmd...> は <cmd> をそのまま実行する（HOME だけ切り替える）。
stub "$stubs/sudo" <<'EOF'
#!/bin/bash
echo "sudo $*" >>"$STUB_LOG"
if [ "$1" = "-l" ]; then
    echo "    (ALL) NOPASSWD: ALL"
    exit 0
fi
while [ $# -gt 0 ]; do
    case "$1" in
    -u) shift 2 ;;
    -H) export HOME="$STUB_HOME"; shift ;;
    *) break ;;
    esac
done
exec "$@"
EOF
stub "$stubs/visudo" <<'EOF'
#!/bin/bash
echo "visudo $*" >>"$STUB_LOG"
EOF
stub "$stubs/chown" <<'EOF'
#!/bin/bash
echo "chown $*" >>"$STUB_LOG"
EOF
# install: 呼ばれ方を記録し、/etc 以外へは実際にコピーする（root 権限の -o / -g は無視する）。
stub "$stubs/install" <<'EOF'
#!/bin/bash
echo "install $*" >>"$STUB_LOG"
args=()
while [ $# -gt 0 ]; do
    case "$1" in
    -m | -o | -g) shift 2 ;;
    *) args+=("$1"); shift ;;
    esac
done
src="${args[0]}"
dst="${args[1]}"
case "$dst" in
/etc/*) exit 0 ;;
esac
cp "$src" "$dst"
chmod 755 "$dst"
EOF
stub "$stubs/xcode-select" <<'EOF'
#!/bin/bash
[ -n "${STUB_NO_CLT:-}" ] && exit 2
echo /Library/Developer/CommandLineTools
EOF
stub "$stubs/brew" <<'EOF'
#!/bin/bash
echo "brew $*" >>"$STUB_LOG"
if [ "$1" = list ]; then
    case " ${STUB_BREW_MISSING:-} " in
    *" $3 "*) exit 1 ;;
    esac
fi
exit 0
EOF
stub "$stubs/launchctl" <<'EOF'
#!/bin/bash
echo "launchctl $*" >>"$STUB_LOG"
# launchctl list <label> は、読み込み済みなら 0・未読み込みなら非 0（実機と同じ）。
if [ "$1" = list ]; then
    grep -qxF "$2" "$STUB_LAUNCHD_LIST" 2>/dev/null
    exit $?
fi
exit 0
EOF
# 実機の plutil -lint の代わり（このホストに別物の plutil があっても影響されないようにする）
stub "$stubs/plutil" <<'EOF'
#!/bin/bash
echo "plutil $*" >>"$STUB_LOG"
EOF
stub "$stubs/pgrep" <<'EOF'
#!/bin/bash
exit 1
EOF
stub "$stubs/sleep" <<'EOF'
#!/bin/bash
exit 0
EOF

# --- runner ユーザーの最小環境（安定 PATH）から見えるコマンド ----------------------
stub "$home/.local/bin/docker" <<'EOF'
#!/bin/bash
echo "docker $*" >>"$STUB_LOG"
echo "Docker stub"
EOF
stub "$home/.local/bin/cc" <<'EOF'
#!/bin/bash
exit 0
EOF
stub "$fnm_bin/node" <<'EOF'
#!/bin/sh
exit 0
EOF
cp "$fnm_bin/node" "$fnm_bin/npx"

# --- runner ディレクトリ: 登録済み（.runner）と、macOS の svc.sh を模したスタブ ----------
echo '{}' >"$runner_dir/.runner"
stub "$runner_dir/svc.sh" <<'EOF'
#!/bin/bash
# macOS の svc.sh（darwin.svc.sh.template）と同じく、plist は $HOME/Library/LaunchAgents へ作り、
# ProgramArguments は <runner root>/runsvc.sh の 1 要素にする。
label=actions.runner.test
plist="$HOME/Library/LaunchAgents/$label.plist"
echo "svc.sh $*" >>"$STUB_LOG"
case "$1" in
install)
    mkdir -p "$(dirname "$plist")"
    cat >"$plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<plist version="1.0">
  <dict>
    <key>Label</key>
    <string>$label</string>
    <key>ProgramArguments</key>
    <array>
      <string>$PWD/runsvc.sh</string>
    </array>
  </dict>
</plist>
PLIST
    printf '#!/bin/bash\necho "runsvc.sh cwd=$PWD" >>"%s"\n' "$STUB_LOG" >runsvc.sh
    chmod +x runsvc.sh
    echo "$plist" >.service
    ;;
start) echo "$label" >>"$STUB_LAUNCHD_LIST" ;;
stop) : >"$STUB_LAUNCHD_LIST" ;;
esac
exit 0
EOF

run_setup() { # run_setup [VAR=value ...] : 出力を $out、終了コードを $rc に入れる
    out=$(env PATH="$stubs:$PATH" RUNNER_USER=ci "$@" bash "$SETUP" 2>&1)
    rc=$?
}

calls() { grep -c "^$1" "$STUB_LOG" || true; }

# --- Intel の Mac は対象外メッセージを出して、何も触らずに止まる ---------------------
: >"$STUB_LOG"
run_setup STUB_UNAME_M=x86_64
check_eq    "Intel Mac: 失敗で止まる"             1 "$rc"
check_match "Intel Mac: 対象外と分かる"           "Intel の Mac は対象外" "$out"
check_eq    "Intel Mac: 何も実行しない"           0 "$(wc -l <"$STUB_LOG")"

# --- Linux / macOS 以外も止まる ---------------------------------------------------
run_setup STUB_UNAME_S=FreeBSD
check_eq    "未対応 OS: 失敗で止まる"             1 "$rc"
check_match "未対応 OS: 対象外と分かる"           "対象外です" "$out"

# --- dscl で引けないユーザーは止まる -------------------------------------------------
run_setup RUNNER_USER=ghost
check_eq    "ユーザー不在: 失敗で止まる"          1 "$rc"
check_match "ユーザー不在: メッセージ"            "ユーザーが見つかりません: ghost" "$out"

# --- 足りない依存は入れ方を案内して止まる（サービス化まで進まない） -------------------
: >"$STUB_LOG"
run_setup STUB_NO_CLT=1
check_eq    "CLT 無し: 失敗で止まる"              1 "$rc"
check_match "CLT 無し: 入れ方を案内する"          "xcode-select --install" "$out"

run_setup STUB_BREW_MISSING="colima docker-buildx"
check_eq    "brew パッケージ不足: 失敗で止まる"    1 "$rc"
check_match "brew パッケージ不足: 入れ方を案内する" "brew install colima docker-buildx" "$out"
check_eq    "依存不足: colima を起動しない"        0 "$(calls 'brew services')"
check_eq    "依存不足: サービス化しない"          0 "$(calls 'svc.sh install')"

# --- 通常の実行 ---------------------------------------------------------------
: >"$STUB_LOG"
: >"$STUB_LAUNCHD_LIST"
run_setup
check_eq    "macOS: 成功する"                     0 "$rc"
check_match "macOS: dscl で取ったホームの runner dir を使う" "runner dir : $runner_dir" "$out"
check_match "macOS: sudoers は wheel グループで置く" "install -m 0440 -o root -g wheel" "$(cat "$STUB_LOG")"
check_match "macOS: colima を brew services で自動起動にする" "brew services start colima" "$(cat "$STUB_LOG")"
check_match "macOS: runner ユーザーで docker info を確かめる" "docker info" "$(cat "$STUB_LOG")"
check_eq    "macOS: svc.sh install を 1 回呼ぶ"   1 "$(calls 'svc.sh install')"
check_eq    "macOS: svc.sh start を 1 回呼ぶ"     1 "$(calls 'svc.sh start')"
check_eq    ".path は macOS の安定 PATH"          "$(runner_stable_path "$home")" "$(<"$runner_dir/.path")"
check_match ".path に /opt/homebrew/bin を含む"    "/opt/homebrew/bin" "$(<"$runner_dir/.path")"
check_no_match ".path に Linux 専用の /snap/bin を含まない" "/snap/bin" "$(<"$runner_dir/.path")"
check_eq    ".env に PATH を 1 行だけ書く"        "PATH=$(<"$runner_dir/.path")" "$(grep '^PATH=' "$runner_dir/.env")"
plist="$home/Library/LaunchAgents/actions.runner.test.plist"
check_match "plist: ガード経由で起動する"         "<string>$runner_dir/path-guard.sh</string>" "$(<"$plist")"
check_match "plist: --exec を渡す"                "<string>--exec</string>" "$(<"$plist")"
check_no_match "plist: runsvc.sh を直接起動しない" "<string>$runner_dir/runsvc.sh</string>" "$(<"$plist")"
check_match "終わりの案内は macOS / ARM64 のラベル" "[self-hosted, macOS, ARM64]" "$out"
check_no_match "macOS: Linux のラベルを出さない"  "[self-hosted, linux, x64]" "$out"

# --- 2 回続けて回しても壊れない（plist も .path も再起動もそのまま） -------------------
before_plist=$(cat "$plist")
before_path=$(cat "$runner_dir/.path")
: >"$STUB_LOG"
run_setup
check_eq    "2 回目: 成功する"                    0 "$rc"
check_eq    "2 回目: plist は変わらない"          "$before_plist" "$(cat "$plist")"
check_eq    "2 回目: .path は変わらない"          "$before_path" "$(cat "$runner_dir/.path")"
check_eq    "2 回目: サービス化し直さない"        0 "$(calls 'svc.sh install')"
check_eq    "2 回目: 起動済みなので start しない" 0 "$(calls 'svc.sh start')"
check_eq    "2 回目: 再起動しない"                0 "$(calls 'svc.sh stop')"

# --- .path を壊してから再実行すると直り、稼働中の runner は再起動される -------------------
echo "/run/user/501/fnm_multishells/1_2/bin:/usr/bin:/bin" >"$runner_dir/.path"
: >"$STUB_LOG"
run_setup
check_eq    "壊れた .path: 成功する"              0 "$rc"
check_eq    "壊れた .path: 安定 PATH に直る"      "$before_path" "$(cat "$runner_dir/.path")"
check_eq    "壊れた .path: 稼働中の runner を stop する"  1 "$(calls 'svc.sh stop')"
check_eq    "壊れた .path: stop の後で start する"        1 "$(calls 'svc.sh start')"

# --- launchd が起動するとき（plist の ProgramArguments）の動き --------------------------
# plist の引数をそのまま実行して、launchd の起動を再現する。
echo "/run/user/501/fnm_multishells/1_2/bin:/usr/bin:/bin" >"$runner_dir/.path"
: >"$STUB_LOG"
launch_out=$(env -i HOME="$home" STUB_LOG="$STUB_LOG" PATH="$stubs:/usr/bin:/bin" "$runner_dir/path-guard.sh" --exec "$runner_dir" "$home" 2>&1)
launch_rc=$?
check_eq    "launchd 起動: runsvc.sh まで進む"     0 "$launch_rc"
check_eq    "launchd 起動: 起動前に .path を直す"  "$before_path" "$(cat "$runner_dir/.path")"
check_match "launchd 起動: 修復を出力する"         "path-guard: $runner_dir/.path を安定 PATH に修復する" "$launch_out"
check_match "launchd 起動: runner dir で runsvc.sh を実行する" "runsvc.sh cwd=$runner_dir" "$(cat "$STUB_LOG")"

# 正常な .path なら触らずに runsvc.sh へ進む
: >"$STUB_LOG"
env -i HOME="$home" STUB_LOG="$STUB_LOG" PATH="$stubs:/usr/bin:/bin" "$runner_dir/path-guard.sh" --exec "$runner_dir" "$home" >/dev/null 2>&1
check_eq    "launchd 起動: 正常な .path は触らない" "$before_path" "$(cat "$runner_dir/.path")"
check_match "launchd 起動: 正常でも runsvc.sh へ進む" "runsvc.sh cwd=$runner_dir" "$(cat "$STUB_LOG")"

# 引数が足りなければ失敗する（何も起動しない）
: >"$STUB_LOG"
env -i STUB_LOG="$STUB_LOG" PATH="$stubs:/usr/bin:/bin" "$runner_dir/path-guard.sh" --exec >/dev/null 2>&1
check_eq    "launchd 起動: 引数不足は失敗する"     1 "$?"
check_eq    "launchd 起動: 引数不足では runsvc.sh を実行しない" 0 "$(calls 'runsvc.sh')"

# --- 別 runner（ラベルが自分の前方一致）が読み込み済みでも、自分は起動する -------------------
rm -f "$runner_dir/.service" "$runner_dir/.path"
rm -rf "$home/Library"
echo "actions.runner.test2" >"$STUB_LAUNCHD_LIST"
: >"$STUB_LOG"
run_setup
check_eq    "ラベルが前方一致の別 runner: 成功する"          0 "$rc"
check_eq    "ラベルが前方一致の別 runner: 自分は start する" 1 "$(calls 'svc.sh start')"
check_eq    "ラベルが前方一致の別 runner: 再起動と取り違えない" 0 "$(calls 'svc.sh stop')"

# --- plist が想定と違うときは壊さずに止まる ----------------------------------------
rm -f "$runner_dir/.service"
rm -rf "$home/Library"
mkdir -p "$home/Library/LaunchAgents"
printf '<plist>\n<array>\n<string>/somewhere/else.sh</string>\n</array>\n</plist>\n' >"$plist"
echo "$plist" >"$runner_dir/.service"
odd=$(cat "$plist")
run_setup
check_eq    "想定外の plist: 失敗で止まる"        1 "$rc"
check_match "想定外の plist: 理由を出す"          "ProgramArguments が想定と違う" "$out"
check_eq    "想定外の plist: 書き換えない"        "$odd" "$(cat "$plist")"

exit "$fail"
