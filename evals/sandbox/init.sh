#!/usr/bin/env bash
# eval 専用の隔離フォルダを作る。ユーザーの HOME・~/.claude・~/.omp・~/dotfiles・gh のログインには触れない。
#
#   evals/sandbox/init.sh [--root DIR] [--ref REF] [--dotfiles-url URL]
#
#   --root          隔離フォルダ（既定 /mnt/nvme/eval-sandbox）。何度実行しても同じ結果になる
#   --ref           試験対象の dotfiles のブランチかタグ（既定 main）。スキル・設定はこの版が使われる。
#                   evals/ がまだ main に無いときは、evals/ を含むブランチを指定する
#   --dotfiles-url  dotfiles の取得元（既定 https://github.com/ousiass/dotfiles.git。公開 repo なので認証は要らない）
#
# 作るもの（すべて --root の下。内容は evals/sandbox/README.md）:
#   dotfiles/   試験対象の dotfiles の clone（--ref の先端。ユーザーのチェックアウトとは別物）
#   home/       ハーネス用の HOME。.claude/ と .omp/agent/ に、dotfiles の設定をリンクで置く（MCP は置かない）
#   work/tmp/   実行ごとの作業フォルダ（TMPDIR）
#   results/    results.jsonl の出力先
#   env.sh      ハーネスを動かす前に source する。HOME・設定ディレクトリ・gh の設定の置き場・認証情報を隔離する
set -uo pipefail

root=/mnt/nvme/eval-sandbox
ref=main
url=https://github.com/ousiass/dotfiles.git
while [[ $# -gt 0 ]]; do
    case "$1" in
    --root | --ref | --dotfiles-url)
        [[ $# -ge 2 ]] || {
            echo "init.sh: $1 に値が必要です" >&2
            exit 2
        }
        case "$1" in
        --root) root="$2" ;;
        --ref) ref="$2" ;;
        --dotfiles-url) url="$2" ;;
        esac
        shift 2
        ;;
    -h | --help)
        sed -n '2,19p' "${BASH_SOURCE[0]}"
        exit 0
        ;;
    *)
        echo "init.sh: 不明な引数: $1" >&2
        exit 2
        ;;
    esac
done

die() {
    echo "init.sh: $*" >&2
    exit 1
}

case "$root" in
/*) ;;
*) die "--root は絶対パスで指定してください: ${root}" ;;
esac
# ユーザーの領域の中には作らない（HOME 直下そのもの・~/dotfiles・~/.claude・~/.omp の中）
for guard in "${HOME:-/nonexistent}" "${HOME:-/nonexistent}/dotfiles" "${HOME:-/nonexistent}/.claude" "${HOME:-/nonexistent}/.omp"; do
    [[ "$root" != "$guard" ]] || die "--root がユーザーの領域です: ${root}"
done
case "$root" in
"${HOME:-/nonexistent}/.claude"/* | "${HOME:-/nonexistent}/.omp"/* | "${HOME:-/nonexistent}/dotfiles"/*) die "--root がユーザーの領域の中です: ${root}" ;;
esac
if [[ -e "$root" && ! -f "$root/.eval-sandbox" ]]; then
    [[ -d "$root" && -z "$(ls -A "$root")" ]] || die "${root} は既に在り、eval の隔離フォルダではありません（.eval-sandbox が無い）。別の場所を指定するか、空にしてください"
fi

# このスクリプト自身の git 設定はホストのものを読まない（clone と checkout だけに使う）
export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1

mkdir -p "$root/home" "$root/work/tmp" "$root/results" || die "${root} を作れない"
printf 'eval sandbox for ousiass/dotfiles evals/（evals/sandbox/init.sh が作った）\n' >"$root/.eval-sandbox"

# --- 試験対象の dotfiles -------------------------------------------------------------
if [[ ! -d "$root/dotfiles/.git" ]]; then
    git clone -q "$url" "$root/dotfiles" || die "dotfiles を clone できない: ${url}"
else
    git -C "$root/dotfiles" fetch -q origin || die "dotfiles を fetch できない"
fi
# 先端をそのまま使う（ローカルの変更は作らない。作業ツリーは常に clean）
git -C "$root/dotfiles" checkout -q --detach "origin/${ref}" 2>/dev/null \
    || git -C "$root/dotfiles" checkout -q --detach "$ref" 2>/dev/null \
    || die "dotfiles に ref が無い: ${ref}"
src="$root/dotfiles"
home="$root/home"

link() { # link <target-in-home> <source>
    local dst="$1" from="$2"
    [[ -e "$from" ]] || die "リンク元が無い: ${from}（--ref を確認してください）"
    mkdir -p "$(dirname "$dst")"
    ln -sfn "$from" "$dst"
}

# --- Claude Code（HOME/.claude）---------------------------------------------------------
# install.sh は ~/.claude 全体を dotfiles/.claude へのリンクにするが、ここでは実体のディレクトリを作り、必要なものだけをリンクする。
# （セッションなどの実行時データを dotfiles の clone に書かせない）
mkdir -p "$home/.claude"
link "$home/.claude/CLAUDE.md" "$src/.claude/CLAUDE.md"
link "$home/.claude/skills" "$src/.claude/skills"
link "$home/.claude/agents" "$src/.claude/agents"
link "$home/.claude/hooks" "$src/.claude/hooks"
# settings.json は複製して、テレメトリ（プロンプトの送信を含む）だけ外す。ほかは dotfiles の設定のまま
rm -f "$home/.claude/settings.json"
jq 'del(.env.CLAUDE_CODE_ENABLE_TELEMETRY, .env.OTEL_LOG_TOOL_DETAILS, .env.OTEL_LOG_USER_PROMPTS)' "$src/.claude/settings.json" >"$home/.claude/settings.json" \
    || die "settings.json を作れない"

# --- omp（HOME/.omp/agent）--------------------------------------------------------------
# install.sh の link_omp と同じ対応（claude-mcp/mcp.json は置かない: MCP サーバー（supabase など）に繋がせない）
mkdir -p "$home/.omp/agent"
link "$home/.omp/agent/config.yml" "$src/omp/config.yml"
link "$home/.omp/agent/RULES.md" "$src/.claude/CLAUDE.md"
link "$home/.omp/agent/WATCHDOG.md" "$src/omp/WATCHDOG.md"
link "$home/.omp/agent/agents" "$src/omp/agents"
link "$home/.omp/agent/extensions" "$src/omp/extensions"
link "$home/.omp/agent/skills" "$src/omp/skills"

# --- git・gh ----------------------------------------------------------------------------
# git の設定は隔離した HOME のものだけ。認証は gh の credential helper を通し、トークンは環境変数 GH_TOKEN から来る
mkdir -p "$home/.config/gh"
cat >"$home/.gitconfig" <<'EOF'
[user]
	name = eval
	email = eval@example.invalid
[init]
	defaultBranch = main
[credential "https://github.com"]
	helper =
	helper = !gh auth git-credential
[commit]
	gpgsign = false
EOF

# --- env.sh ------------------------------------------------------------------------------
cat >"$root/env.sh" <<EOF
# eval 専用の環境。source して使う（evals/sandbox/README.md）。--root を変えたら init.sh を再実行して作り直す。
# 実行したシェルの環境だけが変わる。ユーザーの設定ファイルは書き換えない。
EVAL_SANDBOX_ROOT='$root'
export EVAL_SANDBOX_ROOT

# 設定・セッション・キャッシュ・作業フォルダを隔離する
export HOME="\$EVAL_SANDBOX_ROOT/home"
export XDG_CONFIG_HOME="\$HOME/.config" XDG_CACHE_HOME="\$HOME/.cache" XDG_DATA_HOME="\$HOME/.local/share" XDG_STATE_HOME="\$HOME/.local/state"
export CLAUDE_CONFIG_DIR="\$HOME/.claude"
export PI_CODING_AGENT_DIR="\$HOME/.omp/agent"
export TMPDIR="\$EVAL_SANDBOX_ROOT/work/tmp"
export EVAL_RESULTS_DIR="\$EVAL_SANDBOX_ROOT/results"
mkdir -p "\$TMPDIR" "\$EVAL_RESULTS_DIR" "\$XDG_CONFIG_HOME" "\$XDG_CACHE_HOME" "\$XDG_DATA_HOME" "\$XDG_STATE_HOME"

# git: 隔離した HOME の設定だけ。ユーザーの ssh エージェント・鍵・git の設定を使わせない
export GIT_CONFIG_GLOBAL="\$HOME/.gitconfig" GIT_CONFIG_NOSYSTEM=1
unset SSH_AUTH_SOCK GIT_SSH_COMMAND GIT_SSH GIT_ASKPASS SSH_ASKPASS

# gh: ログイン情報の置き場を隔離する（ユーザーの ~/.config/gh は見ない）。認証は GH_TOKEN だけ
export GH_CONFIG_DIR="\$HOME/.config/gh"
unset GH_TOKEN GITHUB_TOKEN GH_ENTERPRISE_TOKEN GITHUB_ENTERPRISE_TOKEN
# 試験用 repo だけに書ける fine-grained トークン。EVAL_GH_TOKEN（環境変数）か、\$EVAL_SANDBOX_ROOT/gh-token（ファイル、mode 600）
if [ -n "\${EVAL_GH_TOKEN:-}" ]; then
    export GH_TOKEN="\$EVAL_GH_TOKEN"
elif [ -r "\$EVAL_SANDBOX_ROOT/gh-token" ]; then
    GH_TOKEN="\$(tr -d '[:space:]' <"\$EVAL_SANDBOX_ROOT/gh-token")"
    export GH_TOKEN
fi
unset EVAL_GH_TOKEN

# 課金: サブスクリプションの枠で回す。API キーが環境に残っていると、そちらで課金されるので外す
unset ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY MISTRAL_API_KEY GROQ_API_KEY XAI_API_KEY CEREBRAS_API_KEY
# テレメトリは出さない
unset CLAUDE_CODE_ENABLE_TELEMETRY OTEL_EXPORTER_OTLP_ENDPOINT OTEL_LOG_USER_PROMPTS OTEL_LOG_TOOL_DETAILS
EOF

# 呼び出し元のシェルを汚さないための入口。`with-env <コマンド...>` は、env.sh を読み込んだ別プロセスでコマンドを実行する
cat >"$root/with-env" <<'EOF'
#!/usr/bin/env bash
# eval 専用の環境でコマンドを実行する。例: ./with-env dotfiles/evals/run.sh --harness claude --dry
here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
. "$here/env.sh"
[ "$#" -gt 0 ] || { echo "使い方: $0 <コマンド...>" >&2; exit 2; }
exec "$@"
EOF
chmod +x "$root/with-env"

echo "init.sh: 完了: ${root}"
echo "  試験対象の dotfiles: $(git -C "$root/dotfiles" rev-parse --short HEAD)（${ref}）"
echo "  次: ${root}/with-env ${root}/dotfiles/evals/sandbox/doctor.sh"
