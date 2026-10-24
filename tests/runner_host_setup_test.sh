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
    # 先に消す。同名のシンボリックリンク（実物の jq など）があっても、リンク先を上書きしない。
    rm -f "$1"
    cat >"$1"
    chmod +x "$1"
}

# runner-tools-install.sh が ~/.docker/config.json の編集に使う jq は実物を使う。PATH を絞るケースでも
# 見えるよう、スタブ置き場に張る（Homebrew の jq が /opt/homebrew/bin にだけある Mac でも同じ）。
if ! real_jq="$(command -v jq)"; then
    ng "jq が必要です（runner-tools-install.sh の docker 設定の検査に使う）"
    exit 1
fi
ln -sf "$real_jq" "$stubs/jq"

# brew --prefix の値（brew の docker-buildx が置かれる場所もここ）と、docker context の一覧（スタブの状態）
export STUB_BREW_PREFIX="$tmp/brew-prefix"
export STUB_CONTEXTS="$tmp/contexts"
plugin_dir="$STUB_BREW_PREFIX/lib/docker/cli-plugins"
mkdir -p "$plugin_dir"
: >"$STUB_CONTEXTS"

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
-u) echo "${STUB_ID_U:-0}" ;;
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
    -u) export STUB_ID_U=501; shift 2 ;;
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
/etc/*)
    echo "LEAK: /etc への書き込み: $dst" >>"$STUB_LOG"
    exit 99
    ;;
esac
cp "$src" "$dst"
chmod 755 "$dst"
EOF
# macOS の arm64 判定（Rosetta 下では uname -m が x86_64 でも hw.optional.arm64 は 1）
stub "$stubs/sysctl" <<'EOF'
#!/bin/bash
echo "${STUB_ARM64:-0}"
EOF
# Linux 分岐が呼ぶコマンド（実際の apt / systemd / docker / グループには触れない）
stub "$stubs/apt-get" <<'EOF'
#!/bin/bash
echo "apt-get $*" >>"$STUB_LOG"
EOF
stub "$stubs/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >>"$STUB_LOG"
if [ "$1" = is-active ]; then
    [ -n "${STUB_ACTIVE:-}" ]
    exit $?
fi
exit 0
EOF
stub "$stubs/usermod" <<'EOF'
#!/bin/bash
echo "usermod $*" >>"$STUB_LOG"
EOF
stub "$stubs/getent" <<'EOF'
#!/bin/bash
case "$1 $2" in
"passwd ci") echo "ci:x:1000:1000::$STUB_HOME:/bin/bash" ;;
"group docker") echo "docker:x:999:ci" ;;
*) exit 2 ;;
esac
EOF
stub "$stubs/gcc" <<'EOF'
#!/bin/bash
echo "gcc (stub) 1.0"
EOF
# docker（runner-tools-install.sh と Linux の確認が使う側）。context の inspect / create / use を模す。
# use は config.json の currentContext を書き換える（実物と同じ）。
stub "$stubs/docker" <<'EOF'
#!/bin/bash
echo "docker $*" >>"$STUB_LOG"
case "$1 $2" in
"context inspect") grep -qxF "$3" "$STUB_CONTEXTS" ;;
"context create") echo "$3" >>"$STUB_CONTEXTS" ;;
"context use")
    t=$(mktemp)
    jq --arg c "$3" '.currentContext = $c' "$HOME/.docker/config.json" >"$t" && cat "$t" >"$HOME/.docker/config.json"
    rm -f "$t"
    ;;
*) echo "Docker stub" ;;
esac
EOF
# macOS のコンソールユーザー（stat -f %Su /dev/console）。GUI ログイン中のユーザー名を返す。
stub "$stubs/stat" <<'EOF'
#!/bin/bash
echo "stat $*" >>"$STUB_LOG"
if [ "$*" = "-f %Su /dev/console" ]; then
    echo "${STUB_CONSOLE_USER:-ci}"
    exit 0
fi
echo "stat stub: 想定外の引数: $*" >&2
exit 1
EOF
# fnm: default の node があるか（STUB_NO_NODE_DEFAULT で無い状態にする）。install / default は記録だけ。
stub "$stubs/fnm" <<'EOF'
#!/bin/bash
echo "fnm $*" >>"$STUB_LOG"
if [ "$1" = exec ]; then
    [ -z "${STUB_NO_NODE_DEFAULT:-}" ]
    exit $?
fi
exit 0
EOF
stub "$stubs/security" <<'EOF'
#!/bin/bash
echo "     0 valid identities found"
EOF
stub "$stubs/xcode-select" <<'EOF'
#!/bin/bash
[ -n "${STUB_NO_CLT:-}" ] && exit 2
echo /Library/Developer/CommandLineTools
EOF
stub "$stubs/brew" <<'EOF'
#!/bin/bash
echo "brew $*" >>"$STUB_LOG"
[ "$1" = --prefix ] && echo "$STUB_BREW_PREFIX"
if [ "$1" = list ]; then
    case " ${STUB_BREW_MISSING:-} " in
    *" $3 "*) exit 1 ;;
    esac
fi
[ "$1" = install ] && case " ${STUB_BREW_INSTALL_FAIL:-} " in
*" $2 "*) exit 1 ;;
esac
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
# 安定 PATH は macOS で /opt/homebrew/bin を $home/.local/bin より前に持つ。Homebrew のある Mac では、
# そこにある本物の docker が先に見つかり、スタブの docker info が呼ばれずに本物が colima を探して
# 失敗していた（macOS の成功系が全部 exit 1 になった原因）。そこで、安定 PATH の先頭にある
# fnm の aliases/default/bin に docker / cc / node のスタブを置く（本物の /opt/homebrew/bin より前になる）。
# 実機の挙動を再現する（#53）。colima の docker に繋がるのは、$HOME/.docker/config.json の currentContext が
# colima のときだけ（素の状態は /var/run/docker.sock を見て失敗する）。docker buildx も、config.json の
# cliPluginsExtraDirs が設定されているときだけ使える。runner-tools-install.sh が書いた設定を、runner ユーザーの
# 最小環境（env -i）から確かめる。env -i で STUB_LOG が消えていても、エラーを出さない。
stub "$fnm_bin/docker" <<'EOF'
#!/bin/bash
[ -z "${STUB_LOG:-}" ] || echo "docker $*" >>"$STUB_LOG"
cfg="$HOME/.docker/config.json"
case "$1" in
info)
    if [ "$(jq -r '.currentContext // "default"' "$cfg" 2>/dev/null)" != colima ]; then
        echo "Cannot connect to the Docker daemon at unix:///var/run/docker.sock. Is the docker daemon running?" >&2
        exit 1
    fi
    echo "Server: Docker stub (colima)"
    ;;
buildx)
    if ! jq -e '(.cliPluginsExtraDirs // []) | length > 0' "$cfg" >/dev/null 2>&1; then
        echo "docker: 'buildx' is not a docker command." >&2
        exit 1
    fi
    echo "github.com/docker/buildx stub"
    ;;
*) echo "Docker stub" ;;
esac
EOF
stub "$fnm_bin/cc" <<'EOF'
#!/bin/bash
exit 0
EOF
stub "$fnm_bin/node" <<'EOF'
#!/bin/sh
exit 0
EOF
cp "$fnm_bin/node" "$fnm_bin/npx"

# 守り: runner の安定 PATH で docker / cc / node がスタブに解決されること。ここが崩れると、
# 本物の Homebrew がある Mac だけでテストが落ちる（Linux や擬似環境では気づけない）。
for cmd in docker cc node npx; do
    resolved=$(uname() { echo Darwin; }; env -i PATH="$(runner_stable_path "$home")" "$BASH" --noprofile --norc -c "command -v $cmd")
    check_eq "runner の安定 PATH で $cmd はスタブに解決される（本物の /opt/homebrew/bin より先）" "$fnm_bin/$cmd" "$resolved"
done

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

run_setup() { # run_setup [VAR=value ...] : 出力を ${out}、終了コードを $rc に入れる
    # RUNNER_BREW_PATHS="" で、実機の /opt/homebrew の本物の brew を拾わないようにする（個別のケースで上書きできる）。
    out=$(env PATH="$stubs:$PATH" RUNNER_USER=ci SUDOERS_FILE="$tmp/sudoers-github-runner" RUNNER_BREW_PATHS="" "$@" bash "$SETUP" 2>&1)
    rc=$?
}

calls() { grep -c "^$1" "$STUB_LOG" || true; }

# --- Intel の Mac は対象外メッセージを出して、何も触らずに止まる ---------------------
: >"$STUB_LOG"
run_setup STUB_UNAME_M=x86_64
check_eq    "Intel Mac: 失敗で止まる"             1 "$rc"
check_match "Intel Mac: 対象外と分かる"           "Intel の Mac は対象外" "$out"
check_eq    "Intel Mac: 何も実行しない"           0 "$(( $(wc -l <"$STUB_LOG") ))"

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

# --- Homebrew の探し方（RUNNER_BREW_PATHS）。本物の brew が PATH やこのホストの /opt/homebrew にあっても影響されない ---
# brew のスタブを除いたスタブ置き場と、brew を含むディレクトリを除いた PATH を作る。
nobrew="$tmp/bin-nobrew"
mkdir -p "$nobrew"
for f in "$stubs"/*; do [ "$(basename "$f")" = brew ] || ln -s "$f" "$nobrew/$(basename "$f")"; done
clean_path="$nobrew"
IFS=: read -r -a path_dirs <<<"$PATH"
for d in "${path_dirs[@]}"; do
    [ -x "$d/brew" ] || clean_path="$clean_path:$d"
done
fake_brew_dir="$tmp/opt-homebrew/bin"
mkdir -p "$fake_brew_dir"
cp "$stubs/brew" "$fake_brew_dir/brew"

# (2) 空にすると何も足さないので、brew は見つからず、案内して止まる（自動では入れない）
: >"$STUB_LOG"
run_setup PATH="$clean_path"
check_eq    "Homebrew 無し: 失敗で止まる"                 1 "$rc"
check_match "Homebrew 無し: 入れ方を案内する"             "https://brew.sh" "$out"
check_eq    "Homebrew 無し: ツールを入れようとしない"     0 "$(calls 'brew')"
# (1) 上書きでそこを指せば brew が見つかり、最後まで通る
: >"$STUB_LOG"
run_setup PATH="$clean_path" RUNNER_BREW_PATHS="$fake_brew_dir"
check_eq    "RUNNER_BREW_PATHS の先に brew がある: 成功する" 0 "$rc"
check_match "RUNNER_BREW_PATHS の先に brew がある: その brew を使う" "brew services start colima" "$(cat "$STUB_LOG")"

# 足りない brew パッケージは、runner ユーザーとして brew install で入れる（入っているものは飛ばす）。
run_setup STUB_BREW_MISSING="colima docker-buildx"
check_eq    "brew パッケージ不足: 成功する"                0 "$rc"
check_eq    "brew パッケージ不足: colima を入れる"          1 "$(calls 'brew install colima$')"
check_eq    "brew パッケージ不足: docker-buildx を入れる"   1 "$(calls 'brew install docker-buildx$')"
check_eq    "brew パッケージ不足: そろっている docker は入れない" 0 "$(calls 'brew install docker$')"

# 入れるのに失敗したものがあれば、サービス化まで進まず止まる
: >"$STUB_LOG"
run_setup STUB_BREW_MISSING="colima" STUB_BREW_INSTALL_FAIL="colima"
check_eq    "brew install 失敗: 失敗で止まる"             1 "$rc"
check_match "brew install 失敗: 失敗したものを報告する"   "インストールできなかったもの: colima" "$out"
check_eq    "brew install 失敗: colima を起動しない"      0 "$(calls 'brew services')"
check_eq    "brew install 失敗: サービス化しない"        0 "$(calls 'svc.sh install')"

# runner ユーザーが GUI ログインしていない／別ユーザーがログイン中なら、対象外として止まる
: >"$STUB_LOG"
run_setup STUB_CONSOLE_USER=someone-else
check_eq    "別ユーザーがログイン中: 失敗で止まる"        1 "$rc"
check_match "別ユーザーがログイン中: 対象外と分かる"      "対象外です: macOS では、runner ユーザー（ci）が GUI でログインしている必要" "$out"
check_match "別ユーザーがログイン中: 現在のユーザーを示す" "現在のログインユーザー: someone-else" "$out"
check_eq    "別ユーザーがログイン中: 何も設置しない"      0 "$(( $(calls 'install ') + $(calls 'svc.sh') + $(calls 'brew') ))"
run_setup STUB_CONSOLE_USER=root
check_eq    "ログイン画面（root）: 失敗で止まる"          1 "$rc"
check_match "ログイン画面（root）: 誰もログインしていないと案内する" "いまは誰もログインしていません" "$out"
check_eq    "ログイン画面（root）: 何も設置しない"        0 "$(( $(calls 'install ') + $(calls 'svc.sh') + $(calls 'brew') ))"

# --- 通常の実行 ---------------------------------------------------------------
# 直前までのケース（brew パッケージ不足の成功など）が sudoers・サービス・.path を作っているので、
# 初回の実行として確かめるために消しておく。
rm -f "$tmp/sudoers-github-runner" "$runner_dir/.service" "$runner_dir/.path" "$runner_dir/.env"
rm -rf "$home/Library" "$home/.docker"
: >"$STUB_CONTEXTS"
: >"$STUB_LOG"
: >"$STUB_LAUNCHD_LIST"
run_setup
check_eq    "macOS: 成功する"                     0 "$rc"
check_match "macOS: dscl で取ったホームの runner dir を使う" "runner dir : $runner_dir" "$out"
check_match "macOS: sudoers は wheel グループで置く" "install -m 0440 -o root -g wheel" "$(cat "$STUB_LOG")"
check_match "macOS: colima を brew services で自動起動にする" "brew services start colima" "$(cat "$STUB_LOG")"
check_match "macOS: runner ユーザーで docker info を確かめる" "docker info" "$(cat "$STUB_LOG")"
# 2/5（runner-tools-install.sh）が書いた ~/.docker/config.json で、3/5 と 5/5 の docker が colima に繋がる
# （スタブの docker は currentContext が colima のときだけ info が通る）。素の状態では通らない。
check_eq    "macOS: runner ユーザーの currentContext が colima"      colima "$(jq -r '.currentContext' "$home/.docker/config.json")"
check_eq    "macOS: cliPluginsExtraDirs に buildx の場所"            "$plugin_dir" "$(jq -r '.cliPluginsExtraDirs[0]' "$home/.docker/config.json")"
check_match "macOS: 3/5 で docker info が通ったと表示する"           "docker info が通った" "$out"
check_match "macOS: 5/5 で docker info が通る"                       "OK: ci で docker info が通る" "$out"
check_no_match "macOS: 5/5 で docker / buildx の NG が出ない"        "NG: docker" "$out"
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

# --- Rosetta 下の端末（uname -m が x86_64）でも、CPU が Apple Silicon なら対象外にしない ---------
: >"$STUB_LOG"
run_setup STUB_UNAME_M=x86_64 STUB_ARM64=1
check_eq       "Rosetta: 成功する"          0 "$rc"
check_no_match "Rosetta: 対象外にしない"    "対象外です" "$out"

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

# --- Linux: 動きが変わっていない（/etc・systemd は tmp に向けて、コマンドは全てスタブで流す） ------
# 向け先の差し替え口（SUDOERS_FILE / SYSTEMD_SYSTEM_DIR）を使い、実際の /etc には触らない。
# スタブが漏れて /etc へ書こうとすると install スタブが LEAK を記録して失敗する。
linux_dir="$tmp/linux"
linux_runner="$linux_dir/actions-runner"
linux_sudoers="$linux_dir/sudoers-github-runner"
linux_systemd="$linux_dir/systemd"
mkdir -p "$linux_runner" "$linux_systemd"
echo '{}' >"$linux_runner/.runner"
stub "$linux_runner/svc.sh" <<'EOF'
#!/bin/bash
echo "svc.sh $*" >>"$STUB_LOG"
case "$1" in
install) echo actions.runner.test.service >.service ;;
esac
exit 0
EOF
# 末尾に改行が無く、PATH 以外の行も持つ既存の .env（PATH 行だけが置き換わること）
printf 'FOO=1\nPATH=/old' >"$linux_runner/.env"
linux_stable=$(uname() { echo Linux; }; runner_stable_path "$home")
linux_env=(STUB_UNAME_S=Linux RUNNER_DIR="$linux_runner" SUDOERS_FILE="$linux_sudoers" SYSTEMD_SYSTEM_DIR="$linux_systemd")

: >"$STUB_LOG"
run_setup "${linux_env[@]}"
check_eq    "Linux: 成功する"                             0 "$rc"
check_eq    "Linux: /etc へ書こうとしていない"             0 "$(calls 'LEAK')"
check_eq    "Linux: sudoers の内容"                       "ci ALL=(ALL) NOPASSWD: ALL" "$(cat "$linux_sudoers")"
check_match "Linux: sudoers は root グループで置く"        "install -m 0440 -o root -g root" "$(cat "$STUB_LOG")"
check_match "Linux: apt で docker / buildx / build-essential を入れる" "apt-get install -y docker.io docker-buildx build-essential" "$(cat "$STUB_LOG")"
check_match "Linux: docker を有効化する"                   "systemctl enable --now docker" "$(cat "$STUB_LOG")"
check_match "Linux: docker グループへ入れる"                "usermod -aG docker ci" "$(cat "$STUB_LOG")"
check_eq    "Linux: svc.sh install <user> を呼ぶ"           1 "$(calls 'svc.sh install ci')"
check_eq    "Linux: svc.sh start を呼ぶ"                    1 "$(calls 'svc.sh start')"
check_eq    "Linux: macOS 専用の stat -f を呼ばない"        0 "$(calls 'stat ')"
check_eq    "Linux: brew を呼ばない"                         0 "$(calls 'brew')"
check_eq    "Linux: launchctl を呼ばない"                    0 "$(calls 'launchctl')"
check_eq    "Linux: .path は従来の安定 PATH"               "$linux_stable" "$(<"$linux_runner/.path")"
check_eq    "Linux: .env の PATH 行は 1 行だけ"             "PATH=$linux_stable" "$(grep '^PATH=' "$linux_runner/.env")"
check_eq    "Linux: .env の PATH 以外の行を残す"            "FOO=1" "$(grep '^FOO=' "$linux_runner/.env")"
check_eq    "Linux: .env は 2 行になる"                    2 "$(( $(wc -l <"$linux_runner/.env") ))"
dropin="$linux_systemd/actions.runner.test.service.d/path-guard.conf"
check_eq    "Linux: drop-in の ExecStartPre"               "[Service]
ExecStartPre=\"$linux_runner/path-guard.sh\" \"$linux_runner\" \"$home\"" "$(cat "$dropin")"
check_match "Linux: 終わりの案内は linux / x64 のラベル"    "[self-hosted, linux, x64]" "$out"
check_no_match "Linux: macOS のラベルを出さない"           "[self-hosted, macOS, ARM64]" "$out"
check_eq    "Linux: 初回は稼働中でないので再起動しない"      0 "$(calls 'systemctl restart')"

# 2 回目（稼働中）: 何も変わらず、再起動もしない
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_ACTIVE=1
check_eq    "Linux 2 回目: 成功する"                       0 "$rc"
check_eq    "Linux 2 回目: サービス化し直さない"            0 "$(calls 'svc.sh install')"
check_eq    "Linux 2 回目: 再起動しない"                    0 "$(calls 'systemctl restart')"
check_eq    "Linux 2 回目: .path は変わらない"              "$linux_stable" "$(<"$linux_runner/.path")"

# .path が壊れていて稼働中: 直して、ジョブが無ければ systemctl restart する
echo "/run/user/1000/fnm_multishells/1_2/bin:/usr/bin:/bin" >"$linux_runner/.path"
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_ACTIVE=1
check_eq    "Linux 壊れた .path: 安定 PATH に直る"          "$linux_stable" "$(<"$linux_runner/.path")"
check_eq    "Linux 壊れた .path: systemctl restart する"    1 "$(calls 'systemctl restart')"

exit "$fail"
