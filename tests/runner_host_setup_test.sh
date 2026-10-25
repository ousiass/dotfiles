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

# runner-host-setup.sh が読む RUNNER_* は、ケースごとの指定だけにそろえる。GitHub Actions のジョブは
# RUNNER_NAME="GitHub Actions 1000000041" のような値を環境に持っていて、そのまま引き継ぐと
# RUNNER_NAME の検証（空白を許さない）で止まり、成功系のケースが全部落ちる。
unset RUNNER_BREW_PATHS RUNNER_DIR RUNNER_GH_BIN RUNNER_GROUP RUNNER_NAME RUNNER_ORG RUNNER_REPLACE RUNNER_USER

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
# brew の docker-compose が置く実行ファイル（スタブの docker compose が探す）
: >"$plugin_dir/docker-compose" && chmod +x "$plugin_dir/docker-compose"
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
# dpkg-query -W -f='${db:Status-Status}' <pkg> を模す。STUB_DPKG_STATUS="pkg=状態 ..." にあるパッケージだけ
# その状態（installed / config-files など）を出して成功し、無いパッケージは実機と同じく失敗する。
# 引数の形が違えば失敗させる（判定が別の書式に変わったら気づけるように）。実機の dpkg-query は呼ばない。
stub "$stubs/dpkg-query" <<'EOF'
#!/bin/bash
echo "dpkg-query $*" >>"$STUB_LOG"
[ "$1 $2" = '-W -f=${db:Status-Status}' ] || { echo "dpkg-query stub: 想定外の引数: $*" >&2; exit 2; }
for entry in ${STUB_DPKG_STATUS:-}; do
    if [ "${entry%%=*}" = "$3" ]; then
        echo "${entry#*=}"
        exit 0
    fi
done
echo "dpkg-query: no packages found matching $3" >&2
exit 1
EOF
stub "$stubs/systemctl" <<'EOF'
#!/bin/bash
echo "systemctl $*" >>"$STUB_LOG"
if [ "$1 $2" = "cat docker.service" ]; then
    [ -z "${STUB_NO_DOCKER_SERVICE:-}" ]
    exit $?
fi
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
"compose version") [ -n "${STUB_COMPOSE_PRESENT:-}" ] ;;
"buildx version") [ -z "${STUB_BUILDX_ABSENT:-}" ] ;;
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
compose)
    # cliPluginsExtraDirs のどれかに docker-compose の実行ファイルがあるときだけ通る（実機の探索と同じ）
    found=1
    while IFS= read -r d; do
        [ -x "$d/docker-compose" ] && found=0
    done < <(jq -r '.cliPluginsExtraDirs[]?' "$cfg" 2>/dev/null)
    if [ "$found" -ne 0 ]; then
        echo "docker: 'compose' is not a docker command." >&2
        exit 1
    fi
    echo "Docker Compose version stub"
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
check_eq    "macOS: cliPluginsExtraDirs に buildx / compose の場所"  "$plugin_dir" "$(jq -r '.cliPluginsExtraDirs[0]' "$home/.docker/config.json")"
check_match "macOS: 3/5 で docker info が通ったと表示する"           "docker info が通った" "$out"
check_match "macOS: 5/5 で docker info が通る"                       "OK: ci で docker info が通る" "$out"
check_no_match "macOS: 5/5 で docker / buildx / compose の NG が出ない" "NG: docker" "$out"
check_match "macOS: 5/5 で docker compose version を確かめる"        "docker compose version" "$(cat "$STUB_LOG")"
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
check_eq    "Linux: apt で docker / buildx / compose-v2 / build-essential / zstd を入れる" "apt-get install -y docker.io docker-buildx build-essential zstd docker-compose-v2" "$(grep '^apt-get install' "$STUB_LOG")"
check_eq    "Linux: 入れる前に docker compose version で判定する" 1 "$(( $(grep -n '^docker compose version' "$STUB_LOG" | cut -d: -f1 | head -1) < $(grep -n '^apt-get install' "$STUB_LOG" | cut -d: -f1 | head -1) ))"
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

# docker.io ホストで docker compose が既に通る（手動で plugin を入れた等）なら
# docker-compose-v2 を入れない。zstd などは入れる。
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_COMPOSE_PRESENT=1
check_eq    "Linux compose 済み: 成功する"                  0 "$rc"
check_eq    "Linux compose 済み: docker-compose-v2 を入れない" "apt-get install -y docker.io docker-buildx build-essential zstd" "$(grep '^apt-get install' "$STUB_LOG")"

# Docker 公式 apt の docker-ce ホスト: docker.io は docker-ce と Conflicts なので入れない。
# docker-buildx は docker.io に Depends、docker-compose-v2 は Recommends するので、これらも入れない。
# build-essential と zstd は入れる。docker compose が通る（docker-compose-plugin あり）ホストの実態に合わせる。
docker_ce_status="docker-ce=installed docker-ce-cli=installed"
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_DPKG_STATUS="$docker_ce_status" STUB_COMPOSE_PRESENT=1
check_eq    "Linux docker-ce: 成功する"                     0 "$rc"
check_eq    "Linux docker-ce: build-essential と zstd だけ入れる" "apt-get install -y build-essential zstd" "$(grep '^apt-get install' "$STUB_LOG")"
check_eq    "Linux docker-ce: docker を有効化する"          1 "$(calls 'systemctl enable --now docker')"
check_eq    "Linux docker-ce: docker グループへ入れる"      1 "$(calls 'usermod -aG docker ci')"
check_no_match "Linux docker-ce: plugin があれば NG を出さない" "NG: docker" "$out"

# docker-ce ホストで docker compose がまだ通らなくても（plugin 未導入）、docker-compose-v2 は入れない
# （docker.io を引き込むため）。
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_DPKG_STATUS="$docker_ce_status"
check_eq    "Linux docker-ce・compose 無し: docker-compose-v2 も入れない" "apt-get install -y build-essential zstd" "$(grep '^apt-get install' "$STUB_LOG")"

# docker-ce ホストで buildx / compose の plugin が無い: 止めず（rc 0）、公式 plugin の名前を案内する。
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_DPKG_STATUS="$docker_ce_status" STUB_BUILDX_ABSENT=1
check_eq    "Linux docker-ce・plugin 無し: 止まらず成功する"  0 "$rc"
check_match "Linux docker-ce・plugin 無し: buildx の案内"     "docker-buildx-plugin" "$out"
check_match "Linux docker-ce・plugin 無し: compose の案内"    "docker-compose-plugin" "$out"

# docker-ce が removed 後に設定だけ残る（config-files）ホストは docker-ce ホスト扱いにしない
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_DPKG_STATUS="docker-ce=config-files docker-ce-cli=config-files"
check_eq    "Linux docker-ce が rc: docker.io 経路で入れる"   "apt-get install -y docker.io docker-buildx build-essential zstd docker-compose-v2" "$(grep '^apt-get install' "$STUB_LOG")"

# dpkg がトリガー処理待ち（triggers-pending）でも docker-ce は居るので、docker-ce ホスト扱い（docker.io を入れると衝突する）
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_DPKG_STATUS="docker-ce=triggers-pending docker-ce-cli=triggers-pending"
check_eq    "Linux docker-ce が triggers-pending: docker.io を入れない" "apt-get install -y build-essential zstd" "$(grep '^apt-get install' "$STUB_LOG")"

# docker.io ホストでも docker.service が無ければ（apt は成功したのにユニットが無い異常）理由を出して止まる
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_NO_DOCKER_SERVICE=1
check_eq    "Linux docker.io・service 無し: docker.io は入れようとする" "apt-get install -y docker.io docker-buildx build-essential zstd docker-compose-v2" "$(grep '^apt-get install' "$STUB_LOG")"
check_eq    "Linux docker.io・service 無し: 失敗で止まる"     1 "$rc"

# docker-ce-cli だけ（daemon なし）: docker.io は入れず、docker.service が無いので理由を出して止まる
: >"$STUB_LOG"
run_setup "${linux_env[@]}" STUB_DPKG_STATUS="docker-ce-cli=installed" STUB_NO_DOCKER_SERVICE=1
check_eq    "Linux docker-ce-cli のみ: docker.io を入れない"  "apt-get install -y build-essential zstd" "$(grep '^apt-get install' "$STUB_LOG")"
check_eq    "Linux docker-ce-cli のみ: 失敗で止まる"          1 "$rc"
check_match "Linux docker-ce-cli のみ: 理由を出す"            "docker.service がありません" "$out"
check_eq    "Linux docker-ce-cli のみ: docker を有効化しない" 0 "$(calls 'systemctl enable --now docker')"

# --- runner 本体の取得・登録（runner ディレクトリが無い・本体だけある・登録済み）。トークンは出力に出さない --------------
# gh / curl はスタブ。リリースは偽の tarball（config.sh は .runner と svc.sh を作る）で、digest はその sha256。
# 実機での取得・登録・サービス登録は行わない（PR 本文に未確認として挙げる）。
export STUB_TOKEN="AAAA-secret-registration-token-$$-$RANDOM"
export STUB_PS="$tmp/ps.snapshot"
tarsrc="$tmp/tarsrc"
mkdir -p "$tarsrc/bin" "$tarsrc/externals/node20/bin"
: >"$tarsrc/run.sh"; : >"$tarsrc/bin/Runner.Listener"; : >"$tarsrc/bin/runsvc.sh"; : >"$tarsrc/externals/node20/bin/node"
stub "$tarsrc/bin/installdependencies.sh" <<'EOF'
#!/bin/bash
echo "installdependencies.sh" >>"$STUB_LOG"
[ -z "${STUB_DEPS_FAIL:-}" ] || exit 1
EOF
# 本物の config.sh と同じく、トークンは環境変数 ACTIONS_RUNNER_INPUT_TOKEN でだけ受ける。
# 引数に出ていないこと、プロセス一覧に出ていないことを呼ばれた側から確かめるため、ここで記録する。
stub "$tarsrc/config.sh" <<'EOF'
#!/bin/bash
echo "config.sh $*" >>"$STUB_LOG"
echo "config.sh cwd=$PWD" >>"$STUB_LOG"
case "$*" in *"$STUB_TOKEN"*) echo "LEAK: token in argv" >>"$STUB_LOG" ;; esac
[ "${ACTIONS_RUNNER_INPUT_TOKEN:-}" = "$STUB_TOKEN" ] && echo "config.sh token-env=ok" >>"$STUB_LOG"
# 本物の config.sh は、正しいトークンでなければ（JSON 全体など）登録に失敗する
[ "${ACTIONS_RUNNER_INPUT_TOKEN:-}" = "$STUB_TOKEN" ] || { echo "config.sh: Http response code: Unauthorized" >&2; exit 1; }
ps ax -o command >"$STUB_PS" 2>/dev/null || true
[ -z "${STUB_CONFIG_FAIL:-}" ] || exit 1
echo '{}' >.runner
cp "$STUB_SVC_TEMPLATE" svc.sh
EOF
tar -czf "$tmp/runner.tar.gz" -C "$tarsrc" .
if command -v sha256sum >/dev/null 2>&1; then tar_sha=$(sha256sum "$tmp/runner.tar.gz"); else tar_sha=$(shasum -a 256 "$tmp/runner.tar.gz"); fi
export STUB_TARBALL="$tmp/runner.tar.gz" STUB_DIGEST="sha256:${tar_sha%% *}"
cp "$runner_dir/svc.sh" "$tmp/svc-mac.sh"
cp "$linux_runner/svc.sh" "$tmp/svc-linux.sh"
export STUB_SVC_TEMPLATE="$tmp/svc-mac.sh"
stub "$stubs/gh" <<'EOF'
#!/bin/bash
echo "gh $*" >>"$STUB_LOG"
[ -z "${GH_DEBUG:-}${DEBUG:-}" ] || echo "LEAK: debug env" >>"$STUB_LOG"
case "$1 $2" in
"auth status")
    [ -z "${STUB_GH_UNAUTH:-}" ] || { echo "You are not logged into any GitHub hosts." >&2; exit 1; }
    ;;
"api repos/actions/runner/releases/latest")
    # 本物の jq で、スクリプトの --jq のフィルタをそのまま評価する（フィルタの誤りを通さない）。
    # 本体のほかに -noexternals と .sha と digest 無しを混ぜ、選ぶのが本体の 1 件だけであることを確かめる。
    jq -n --arg d "${STUB_DIGEST:-}" '
      ["osx-arm64", "linux-x64", "linux-arm64"] as $ps
      | {assets: [ $ps[] as $p
          | ("actions-runner-\($p)-9.9.9") as $b
          | {name: "\($b).tar.gz", browser_download_url: "https://github.com/actions/runner/releases/download/v9.9.9/\($b).tar.gz", digest: (if $d == "" then null else $d end)},
            {name: "\($b)-noexternals.tar.gz", browser_download_url: "https://github.com/actions/runner/releases/download/v9.9.9/\($b)-noexternals.tar.gz", digest: "sha256:0000000000000000000000000000000000000000000000000000000000000000"},
            {name: "\($b).tar.gz.sha", browser_download_url: "https://example.invalid/x", digest: null} ]}' | jq -r "$4"
    ;;
"api -X")
    # 本番と同じ形（POST・登録トークンの URL・--jq）でないと失敗させる。--jq .token が無ければ JSON 全体が
    # トークンとして渡って config.sh が失敗する、という実 gh の挙動を再現する。
    [ "$3" = POST ] && case "$4" in orgs/*/actions/runners/registration-token) ;; *) exit 1 ;; esac || exit 1
    [ -z "${STUB_GH_FAIL:-}" ] || { echo "gh: HTTP 403" >&2; exit 1; }
    jq -n --arg t "$STUB_TOKEN" '{token:$t, expires_at:"2099-01-01T00:00:00Z"}' | { [ "$5" = --jq ] && jq -r "$6" || cat; }
    ;;
*) exit 1 ;;
esac
EOF
stub "$stubs/curl" <<'EOF'
#!/bin/bash
echo "curl $*" >>"$STUB_LOG"
while [ $# -gt 0 ]; do
    case "$1" in
    -o) cp "$STUB_TARBALL" "$2"; shift 2 ;;
    *) shift ;;
    esac
done
EOF

# fresh_run <name> [VAR=value ...] : 作り直した runner dir（$fresh）で macOS として実行する
fresh_run() {
    local name="$1"
    shift
    fresh="$tmp/fresh-$name"
    rm -rf "$fresh" "$home/Library"
    : >"$STUB_LOG"; : >"$STUB_LAUNCHD_LIST"; rm -f "$STUB_PS"
    run_setup RUNNER_DIR="$fresh" "$@"
}
# トークンが、出力・呼び出しの記録・runner dir のファイル・プロセス一覧のどこにも無いこと。
# 第 2 引数 ran を付けると、config.sh が走った時点の ps（引数が見える形）が実際に取れていることも確かめる
# （ps が取れずに「トークンは無い」と素通りしないように）。
check_token_hidden() {
    local name="$1" ran="${2:-}"
    check_no_match "$name: 出力にトークンが出ない"           "$STUB_TOKEN" "$out"
    check_no_match "$name: 呼び出しの記録（引数）にトークンが出ない" "$STUB_TOKEN" "$(cat "$STUB_LOG")"
    check_eq       "$name: runner dir のファイルにトークンが無い" 0 "$(grep -rlF "$STUB_TOKEN" "$fresh" 2>/dev/null | wc -l | tr -d ' ')"
    if [ "$ran" = ran ]; then
        check_match "$name: ps のスナップショットが取れている（config.sh の引数が見える）" "--no-default-labels" "$(cat "$STUB_PS" 2>/dev/null)"
    fi
    check_eq       "$name: プロセス一覧の argv にトークンが出ない（環境変数は対象外）" 0 "$( { grep -F "$STUB_TOKEN" "$STUB_PS" 2>/dev/null || true; } | wc -l | tr -d ' ' )"
}
default_name=$(hostname -s)

# (1) macOS・runner ディレクトリが無い: 取得 → 登録 → サービス化まで 1 回で済む
fresh_run mac-new
check_eq    "runner 無し(macOS): 成功する"                       0 "$rc"
check_eq    "runner 無し(macOS): 最新リリースを 1 回だけ引く"    1 "$(calls 'gh api repos/actions/runner/releases/latest')"
check_match "runner 無し(macOS): osx-arm64 を選ぶ"               "actions-runner-osx-arm64-" "$(grep '^gh api repos' "$STUB_LOG")"
check_match "runner 無し(macOS): osx-arm64 の資産を落とす"       "actions-runner-osx-arm64-9.9.9.tar.gz" "$(grep '^curl' "$STUB_LOG")"
check_eq    "runner 無し(macOS): 展開した config.sh が runner dir に在る" 1 "$(grep -c '^config.sh cwd='"$fresh"'$' "$STUB_LOG")"
check_eq    "runner 無し(macOS): 取得の作業ディレクトリを残さない" 0 "$(find "$fresh" -maxdepth 1 -name '.fetch.*' | wc -l | tr -d ' ')"
check_eq    "runner 無し(macOS): 所有者を runner ユーザーに渡す" 1 "$(calls "chown ci $fresh\$")"
check_eq    "runner 無し(macOS): 取得と登録は runner ユーザー（sudo -u ci）で走る" 2 "$(calls 'sudo -u ci -H bash -c')"
check_eq    "runner 無し(macOS): macOS では installdependencies を呼ばない" 0 "$(calls 'installdependencies')"
check_eq    "runner 無し(macOS): ラベルは macOS / ARM64 を自動で付ける" 1 "$(calls "config.sh --unattended --url https://github.com/ousiassllc --name $default_name --runnergroup Default --no-default-labels --labels self-hosted,macOS,ARM64 --work _work\$")"
check_eq    "runner 無し(macOS): 登録トークンは環境変数でだけ config.sh に渡る" 1 "$(calls 'config.sh token-env=ok')"
check_eq    "runner 無し(macOS): 引数にトークンを置かない"       0 "$(calls 'LEAK')"
check_token_hidden "runner 無し(macOS)" ran
check_eq    "runner 無し(macOS): 登録後に svc.sh install する"   1 "$(calls 'svc.sh install')"
check_eq    "runner 無し(macOS): svc.sh start する"              1 "$(calls 'svc.sh start')"
check_eq    "runner 無し(macOS): .runner ができる"               1 "$([ -f "$fresh/.runner" ] && echo 1 || echo 0)"

# (2) 登録済み（.runner がある）の 2 回目: 何も取得・登録しない
: >"$STUB_LOG"
run_setup RUNNER_DIR="$fresh"
check_eq    "登録済み: 成功する"                                 0 "$rc"
check_match "登録済み: 登録済みと表示する"                       "登録済み: $fresh/.runner" "$out"
check_eq    "登録済み: gh を呼ばない"                            0 "$(calls 'gh')"
check_eq    "登録済み: ダウンロードしない"                       0 "$(calls 'curl')"
check_eq    "登録済み: config.sh を呼ばない"                     0 "$(calls 'config.sh')"

# (3) 本体は在るが未登録（.runner が無い）: 再ダウンロードせず登録だけする
rm -rf "$tmp/fresh-body" "$home/Library"
mkdir -p "$tmp/fresh-body"
cp "$tarsrc/config.sh" "$tmp/fresh-body/config.sh"
: >"$STUB_LOG"; : >"$STUB_LAUNCHD_LIST"; rm -f "$STUB_PS"
fresh="$tmp/fresh-body"
run_setup RUNNER_DIR="$fresh"
check_eq    "本体のみ: 成功する"                                 0 "$rc"
check_match "本体のみ: 取得済みと表示する"                       "runner 本体は取得済み" "$out"
check_eq    "本体のみ: ダウンロードしない"                       0 "$(calls 'curl')"
check_eq    "本体のみ: リリースを引かない"                       0 "$(calls 'gh api repos')"
check_eq    "本体のみ: 登録する"                                 1 "$(calls 'config.sh --unattended')"
check_token_hidden "本体のみ" ran

# (4) 変数で org / 名前 / group を指定できる。登録トークンの API も指定した org に向く
fresh_run custom RUNNER_ORG=other-org RUNNER_NAME=my-mac RUNNER_GROUP="My Group"
check_eq    "変数指定: 成功する"                                 0 "$rc"
check_eq    "変数指定: 指定した org でトークンを発行する"         1 "$(calls 'gh api -X POST orgs/other-org/actions/runners/registration-token')"
check_eq    "変数指定: org / 名前 / group で登録する"            1 "$(calls 'config.sh --unattended --url https://github.com/other-org --name my-mac --runnergroup My Group --no-default-labels')"
check_token_hidden "変数指定" ran
fresh_run badorg RUNNER_ORG="a b"
check_eq    "変数指定: 使えない文字の org は止まる"              1 "$rc"
check_match "変数指定: 理由を出す"                               "使えない文字があります" "$out"
check_eq    "変数指定: 何も取得・登録しない"                     0 "$(( $(calls 'gh') + $(calls 'curl') + $(calls 'config.sh') ))"

# (5) チェックサムが一致しなければ展開せず止まる（登録・サービス化まで進まない）
fresh_run badsum STUB_DIGEST="sha256:$(printf '0%.0s' $(seq 1 64))"
check_eq    "チェックサム不一致: 失敗で止まる"                   1 "$rc"
check_match "チェックサム不一致: 理由を出す"                     "チェックサムが一致しません" "$out"
check_eq    "チェックサム不一致: config.sh を置かない"           0 "$([ -e "$fresh/config.sh" ] && echo 1 || echo 0)"
check_eq    "チェックサム不一致: 作業ディレクトリを残さない"     0 "$(find "$fresh" -maxdepth 1 -name '.fetch.*' | wc -l | tr -d ' ')"
check_eq    "チェックサム不一致: 登録しない"                     0 "$(( $(calls 'gh api -X POST') + $(calls 'config.sh') ))"
check_eq    "チェックサム不一致: サービス化しない"               0 "$(calls 'svc.sh')"
fresh_run nodigest STUB_DIGEST=""
check_eq    "digest 無し: 確かめずに入れない（失敗で止まる）"     1 "$rc"
check_match "digest 無し: 理由を出す"                            "sha256 の digest が無い" "$out"
check_eq    "digest 無し: ダウンロードしない"                    0 "$(calls 'curl')"

# (6) 登録の失敗: トークンの発行に失敗しても、config.sh が失敗しても、止まり、トークンは出ない
fresh_run tokfail STUB_GH_FAIL=1
check_eq    "トークン発行失敗: 失敗で止まる"                     1 "$rc"
check_match "トークン発行失敗: 登録に失敗したと案内する"         "登録に失敗しました" "$out"
check_eq    "トークン発行失敗: config.sh を呼ばない"             0 "$(calls 'config.sh --unattended')"
check_eq    "トークン発行失敗: サービス化しない"                 0 "$(calls 'svc.sh')"
check_token_hidden "トークン発行失敗"
fresh_run cfgfail STUB_CONFIG_FAIL=1
check_eq    "config.sh 失敗: 失敗で止まる"                       1 "$rc"
check_eq    "config.sh 失敗: サービス化しない"                   0 "$(calls 'svc.sh')"
check_token_hidden "config.sh 失敗" ran

# (7) Linux: x64 / arm64 で資産とラベルが変わる。依存パッケージ（root）と svc.sh install <user>（root）は今まで通り
linux_boot_env=(STUB_UNAME_S=Linux STUB_SVC_TEMPLATE="$tmp/svc-linux.sh" SUDOERS_FILE="$linux_sudoers" SYSTEMD_SYSTEM_DIR="$linux_systemd")
fresh_run linux-x64 "${linux_boot_env[@]}" STUB_UNAME_M=x86_64
check_eq    "runner 無し(Linux x64): 成功する"                   0 "$rc"
check_match "runner 無し(Linux x64): linux-x64 を選ぶ"           "actions-runner-linux-x64-9.9.9.tar.gz" "$(grep '^curl' "$STUB_LOG")"
check_eq    "runner 無し(Linux x64): ラベルは linux / x64"       1 "$(calls "config.sh --unattended --url https://github.com/ousiassllc --name $default_name --runnergroup Default --no-default-labels --labels self-hosted,linux,x64 --work _work\$")"
check_eq    "runner 無し(Linux x64): 依存パッケージを root で入れる" 1 "$(calls 'installdependencies.sh')"
check_eq    "runner 無し(Linux x64): svc.sh install <user> を呼ぶ" 1 "$(calls 'svc.sh install ci')"
check_token_hidden "runner 無し(Linux x64)" ran
fresh_run linux-arm64 "${linux_boot_env[@]}" STUB_UNAME_M=aarch64
check_eq    "runner 無し(Linux arm64): 成功する"                 0 "$rc"
check_match "runner 無し(Linux arm64): linux-arm64 を選ぶ"       "actions-runner-linux-arm64-9.9.9.tar.gz" "$(grep '^curl' "$STUB_LOG")"
check_eq    "runner 無し(Linux arm64): ラベルは linux / arm64"   1 "$(calls 'config.sh --unattended .* --labels self-hosted,linux,arm64 --work _work$')"
fresh_run linux-unsupported "${linux_boot_env[@]}" STUB_UNAME_M=riscv64
check_eq    "runner 無し(Linux riscv64): 対象外で止まる"          1 "$rc"
check_match "runner 無し(Linux riscv64): 対象外と分かる"          "対象外です" "$out"

# (8) 前提が足りないときは、sudoers・apt・brew より前に（Linux）／取得より前に（macOS）止まる
fresh_run noauth-linux "${linux_boot_env[@]}" STUB_UNAME_M=x86_64 STUB_GH_UNAUTH=1
check_eq    "gh 未認証(Linux): 失敗で止まる"                     1 "$rc"
check_match "gh 未認証(Linux): gh auth login を案内する"         "gh auth login -s admin:org" "$out"
check_eq    "gh 未認証(Linux): sudoers も apt も触る前に止まる"   0 "$(( $(calls 'install ') + $(calls 'apt-get') + $(calls 'visudo') ))"
fresh_run noauth-mac STUB_GH_UNAUTH=1
check_eq    "gh 未認証(macOS): 失敗で止まる"                     1 "$rc"
check_match "gh 未認証(macOS): gh auth login を案内する"         "gh auth login -s admin:org" "$out"
check_eq    "gh 未認証(macOS): ダウンロードしない"               0 "$(calls 'curl')"
check_eq    "gh 未認証(macOS): サービス化しない"                 0 "$(calls 'svc.sh')"
fresh_run nogh-linux "${linux_boot_env[@]}" STUB_UNAME_M=x86_64 RUNNER_GH_BIN=/nonexistent/gh
check_eq    "gh 無し(Linux): 失敗で止まる"                       1 "$rc"
check_match "gh 無し(Linux): 入れ方を案内する"                   "make runner-tools" "$out"
check_eq    "gh 無し(Linux): apt を触る前に止まる"               0 "$(calls 'apt-get')"
fresh_run nogh-mac RUNNER_GH_BIN=/nonexistent/gh
check_eq    "gh 無し(macOS): 失敗で止まる"                       1 "$rc"
check_match "gh 無し(macOS): 入れ方を案内する"                   "make runner-tools" "$out"
fresh_run badname RUNNER_NAME="bad name;rm"
check_eq    "不正な RUNNER_NAME: 止まる"                         1 "$rc"
check_match "不正な RUNNER_NAME: 理由を出す"                     "使えない文字があります" "$out"
fresh_run badgroup RUNNER_GROUP="-x"
check_eq    "不正な RUNNER_GROUP: 止まる"                        1 "$rc"
check_match "不正な RUNNER_GROUP: 理由を出す"                    "使えない文字があります" "$out"

# (9) 展開先の扱い: 無関係なファイルがあるディレクトリには展開しない・所有者も変えない。
#     前回の途中で止まった残り（展開物と同名）は、入れ子にならず置き換わる
rm -rf "$tmp/fresh-busy-x"; mkdir -p "$tmp/fresh-busy-x"; echo precious >"$tmp/fresh-busy-x/my-notes.txt"
: >"$STUB_LOG"; fresh="$tmp/fresh-busy-x"
run_setup RUNNER_DIR="$fresh"
check_eq    "非空ディレクトリ: 失敗で止まる"                     1 "$rc"
check_match "非空ディレクトリ: 理由を出す"                       "空でないディレクトリには展開しません" "$out"
check_eq    "非空ディレクトリ: 既存のファイルをそのまま残す"     precious "$(cat "$fresh/my-notes.txt")"
check_eq    "非空ディレクトリ: config.sh を置かない"             0 "$([ -e "$fresh/config.sh" ] && echo 1 || echo 0)"
check_eq    "非空ディレクトリ: 既存ディレクトリの所有者は変えない" 0 "$(calls 'chown')"
check_eq    "非空ディレクトリ: 登録しない"                       0 "$(calls 'config.sh')"
# 展開物と同名（bin）だけがあってもマーカーが無ければ、ユーザー自身のファイルかもしれないので消さずに止まる
rm -rf "$tmp/fresh-samename"; mkdir -p "$tmp/fresh-samename/bin"; echo mine >"$tmp/fresh-samename/bin/my-tool"
: >"$STUB_LOG"; fresh="$tmp/fresh-samename"
run_setup RUNNER_DIR="$fresh"
check_eq    "同名だけでマーカー無し: 失敗で止まる"               1 "$rc"
check_eq    "同名だけでマーカー無し: 既存のファイルを消さない"   mine "$(cat "$fresh/bin/my-tool")"
# 前回の途中で止まった残り（マーカーあり）は、入れ子にならず置き換わり、終われば（config.sh の後に）マーカーが消える
rm -rf "$tmp/fresh-partial"; mkdir -p "$tmp/fresh-partial/bin"; echo stale >"$tmp/fresh-partial/bin/stale-file"; : >"$tmp/fresh-partial/.runner-extracting"
: >"$STUB_LOG"; fresh="$tmp/fresh-partial"
run_setup RUNNER_DIR="$fresh"
check_eq    "途中で止まった残り: 再実行で成功する"               0 "$rc"
check_eq    "途中で止まった残り: bin が入れ子にならない"         0 "$([ -e "$fresh/bin/bin" ] && echo 1 || echo 0)"
check_eq    "途中で止まった残り: 古い残りは消える"               0 "$([ -e "$fresh/bin/stale-file" ] && echo 1 || echo 0)"
check_eq    "途中で止まった残り: 展開物が揃う"                   1 "$([ -e "$fresh/bin/Runner.Listener" ] && [ -e "$fresh/externals/node20/bin/node" ] && echo 1 || echo 0)"
check_eq    "途中で止まった残り: 終わればマーカーが消える"       0 "$([ -e "$fresh/.runner-extracting" ] && echo 1 || echo 0)"
# 前回 SIGKILL された作業ディレクトリ（.fetch.*）は取得の前に片付く
rm -rf "$tmp/fresh-stage"; mkdir -p "$tmp/fresh-stage/.fetch.OLD123"; echo junk >"$tmp/fresh-stage/.fetch.OLD123/x"
: >"$STUB_LOG"; fresh="$tmp/fresh-stage"
run_setup RUNNER_DIR="$fresh"
check_eq    "古い作業ディレクトリ: 成功する"                     0 "$rc"
check_eq    "古い作業ディレクトリ: 片付く"                       0 "$(find "$fresh" -maxdepth 1 -name '.fetch.*' | wc -l | tr -d ' ')"
# 書き込めない既存ディレクトリには展開しない（所有者も変えない）
# （root は chmod 555 でも書き込めるので、root のときは確かめない）
if [ "$(id -u)" -ne 0 ]; then
    rm -rf "$tmp/fresh-ro"; mkdir -p "$tmp/fresh-ro"; chmod 555 "$tmp/fresh-ro"
    : >"$STUB_LOG"; fresh="$tmp/fresh-ro"
    run_setup RUNNER_DIR="$fresh"
    check_eq    "書き込めないディレクトリ: 失敗で止まる"             1 "$rc"
    check_match "書き込めないディレクトリ: 理由を出す"               "書き込めません" "$out"
    check_eq    "書き込めないディレクトリ: 所有者を変えない"         0 "$(calls 'chown')"
    chmod 755 "$tmp/fresh-ro"
else
    ok "書き込めないディレクトリ: root では確かめない"
fi
# 親ディレクトリが無ければ作らずに止まる（root 所有の中間ディレクトリを残さない）
: >"$STUB_LOG"; fresh="$tmp/no-parent/actions-runner"
run_setup RUNNER_DIR="$fresh"
check_eq    "親ディレクトリ無し: 失敗で止まる"                   1 "$rc"
check_match "親ディレクトリ無し: 理由を出す"                     "親ディレクトリがありません" "$out"
check_eq    "親ディレクトリ無し: 何も作らない"                   0 "$([ -e "$tmp/no-parent" ] && echo 1 || echo 0)"

# (9b) --replace は既定で付けない（RUNNER_DIR の指定ミスや 2 台目で、既存の runner を黙って追い出さない）。
#      RUNNER_REPLACE=1 のときだけ付ける。同名があって config.sh が失敗したら、その案内を出す
fresh_run noreplace
check_eq    "--replace: 既定では付けない"                        0 "$(calls 'config.sh .*--replace')"
check_eq    "--replace: 既定では付けない（成功する）"            0 "$rc"
fresh_run replace RUNNER_REPLACE=1
check_eq    "--replace: RUNNER_REPLACE=1 で付ける"               1 "$(calls 'config.sh --unattended --replace --url')"
fresh_run dupname STUB_CONFIG_FAIL=1
check_match "同名の runner: 失敗時に RUNNER_REPLACE=1 を案内する" "RUNNER_REPLACE=1" "$out"

# (9c) gh のデバッグ出力の環境変数（GH_DEBUG / DEBUG）は、gh に渡さない（応答のトークンが出うるため）
fresh_run debugenv GH_DEBUG=api DEBUG=1
check_eq    "デバッグ環境変数: 成功する"                         0 "$rc"
check_eq    "デバッグ環境変数: gh に渡さない"                    0 "$(calls 'LEAK: debug env')"
check_token_hidden "デバッグ環境変数" ran

# (9d) ダウンロードは https だけ・TLS 1.2 以上・タイムアウト付き
fresh_run curlflags
check_match "curl: https だけ"                                   "--proto =https" "$(grep '^curl' "$STUB_LOG")"
check_match "curl: TLS 1.2 以上"                                 "--tlsv1.2" "$(grep '^curl' "$STUB_LOG")"
check_match "curl: タイムアウト付き"                             "--max-time" "$(grep '^curl' "$STUB_LOG")"

# (9e) macOS: gh が未認証なら、colima を起動して待つ前（2/5 の直後）に止まる。登録済みなら gh を見ない
fresh_run early-mac STUB_GH_UNAUTH=1
check_eq    "gh 未認証(macOS): colima を起動する前に止まる"      0 "$(calls 'brew services')"
# 直前までのケースが作った launchd の状態（.service と plist）を消して、登録済みの初回として流す
rm -f "$runner_dir/.service"; rm -rf "$home/Library"; : >"$STUB_LOG"
run_setup STUB_GH_UNAUTH=1
check_eq    "登録済み(macOS): gh が未認証でも進む"               0 "$rc"
check_eq    "登録済み(macOS): gh の認証を確かめない"             0 "$(calls 'gh auth status')"

# (9f) 登録済み（.runner あり）のホストは、入力の検証も gh も CPU 判定も飛ばして従来どおり進む（回帰防止）
rm -f "$runner_dir/.service"; rm -rf "$home/Library"; : >"$STUB_LOG"
run_setup RUNNER_NAME="bad name;rm" RUNNER_GROUP="-x" RUNNER_REPLACE=bogus RUNNER_GH_BIN=/nonexistent/gh
check_eq    "登録済み: 不正な変数があっても進む"                 0 "$rc"
check_eq    "登録済み: 検証で止まらない"                         0 "$(printf '%s' "$out" | grep -c '使えない文字')"

# (9g) 相対パスの RUNNER_DIR・不正な RUNNER_REPLACE は、何も取得せず止まる
fresh_run relpath RUNNER_DIR=rel/runner
check_eq    "相対パスの RUNNER_DIR: 止まる"                      1 "$rc"
check_match "相対パスの RUNNER_DIR: 絶対パスを案内する"          "絶対パスで指定してください" "$out"
check_eq    "相対パスの RUNNER_DIR: 何も取得しない"              0 "$(( $(calls 'curl') + $(calls 'config.sh') ))"
fresh_run badreplace RUNNER_REPLACE=yes
check_eq    "不正な RUNNER_REPLACE: 止まる"                      1 "$rc"
check_match "不正な RUNNER_REPLACE: 理由を出す"                  "RUNNER_REPLACE は 1" "$out"

# (9h) マーカーの再開: 展開物に無いものがあれば消さず止まる／config.sh まで済んでいればマーカーを片付けて登録へ
rm -rf "$tmp/fresh-resume-x"; mkdir -p "$tmp/fresh-resume-x/bin"; : >"$tmp/fresh-resume-x/.runner-extracting"; echo mine >"$tmp/fresh-resume-x/my-notes.txt"
: >"$STUB_LOG"; fresh="$tmp/fresh-resume-x"
run_setup RUNNER_DIR="$fresh"
check_eq    "再開(展開物に無い物あり): 失敗で止まる"             1 "$rc"
check_match "再開(展開物に無い物あり): 理由を出す"               "前回の展開の続きですが" "$out"
check_eq    "再開(展開物に無い物あり): 既存のファイルを残す"     mine "$(cat "$fresh/my-notes.txt")"
rm -rf "$tmp/fresh-resume-done" "$home/Library"; mkdir -p "$tmp/fresh-resume-done"
cp "$tarsrc/config.sh" "$tmp/fresh-resume-done/config.sh"; : >"$tmp/fresh-resume-done/.runner-extracting"
: >"$STUB_LOG"; : >"$STUB_LAUNCHD_LIST"; fresh="$tmp/fresh-resume-done"
run_setup RUNNER_DIR="$fresh"
check_eq    "再開(config.sh まで済み): 成功する"                 0 "$rc"
check_eq    "再開(config.sh まで済み): 再ダウンロードしない"     0 "$(calls 'curl')"
check_eq    "再開(config.sh まで済み): マーカーを片付ける"       0 "$([ -e "$fresh/.runner-extracting" ] && echo 1 || echo 0)"
check_eq    "再開(config.sh まで済み): 登録する"                 1 "$(calls 'config.sh --unattended')"
# 無関係な中身は、ダウンロードする前に断る
rm -rf "$tmp/fresh-early"; mkdir -p "$tmp/fresh-early"; echo precious >"$tmp/fresh-early/my-notes.txt"; : >"$STUB_LOG"; fresh="$tmp/fresh-early"
run_setup RUNNER_DIR="$fresh"
check_eq    "無関係な中身: ダウンロードする前に止まる"           0 "$(calls 'curl')"
check_eq    "無関係な中身: 失敗で止まる"                         1 "$rc"
# チェックサム不一致では、展開を始めた印（マーカー）を置かない
fresh_run nomarker STUB_DIGEST="sha256:$(printf '1%.0s' $(seq 1 64))"
check_eq    "チェックサム不一致: マーカーを置かない"             0 "$([ -e "$fresh/.runner-extracting" ] && echo 1 || echo 0)"

# (9i) Makefile は sudo の環境リセットを越えて変数を渡す（make runner-setup RUNNER_REPLACE=1 が黙って落ちない）
mk_out=$(make -n -C "$DOTFILES_DIR" runner-setup RUNNER_REPLACE=1 RUNNER_ORG=x RUNNER_NAME=n RUNNER_GROUP=g 2>&1 || true)
check_match "make: RUNNER_REPLACE を sudo に渡す"                'RUNNER_REPLACE="1"' "$mk_out"
check_match "make: RUNNER_ORG を sudo に渡す"                    'RUNNER_ORG="x"' "$mk_out"
check_match "make: RUNNER_NAME を sudo に渡す"                   'RUNNER_NAME="n"' "$mk_out"
check_match "make: RUNNER_GROUP を sudo に渡す"                  'RUNNER_GROUP="g"' "$mk_out"
check_no_match "make: 登録トークンを変数にしない"                 "TOKEN" "$mk_out"

# (10) Linux の依存パッケージ: 失敗したら止まり、再実行でもう一度走る（取得済みの分岐でも飛ばさない）
fresh_run deps-fail "${linux_boot_env[@]}" STUB_UNAME_M=x86_64 STUB_DEPS_FAIL=1
check_eq    "依存導入の失敗(Linux): 失敗で止まる"                1 "$rc"
check_eq    "依存導入の失敗(Linux): 登録しない"                  0 "$(calls 'config.sh')"
check_eq    "依存導入の失敗(Linux): サービス化しない"            0 "$(calls 'svc.sh')"
: >"$STUB_LOG"
run_setup RUNNER_DIR="$fresh" "${linux_boot_env[@]}" STUB_UNAME_M=x86_64
check_eq    "依存導入の再実行(Linux): 成功する"                  0 "$rc"
check_match "依存導入の再実行(Linux): 取得済みと表示する"        "runner 本体は取得済み" "$out"
check_eq    "依存導入の再実行(Linux): もう一度依存を入れる"      1 "$(calls 'installdependencies.sh')"
check_eq    "依存導入の再実行(Linux): 再ダウンロードしない"      0 "$(calls 'curl')"

exit "$fail"
