#!/usr/bin/env bash
# 隔離が効いているかの確認。モデルは呼ばない。`<root>/with-env` の中で実行する:
#
#   /mnt/nvme/eval-sandbox/with-env /mnt/nvme/eval-sandbox/dotfiles/evals/sandbox/doctor.sh [--repo OWNER/NAME]
#
# 確かめること（落ちたら exit 1）:
#   - HOME・設定ディレクトリ・TMPDIR が隔離フォルダの下にある
#   - リンクが解決でき、リンク先が隔離フォルダの dotfiles の中にある
#   - 課金（API キー）・認証（既存の gh ログイン・ssh エージェント）が環境に残っていない
#   - トークンがあるとき: 試験用 repo だけに届くか（--repo を指定したときだけ、読み取り専用の API を呼ぶ）
# トークンの値は表示しない。
set -uo pipefail

repo=ousiass/dotfiles-eval-sandbox
while [[ $# -gt 0 ]]; do
    case "$1" in
    --repo)
        [[ $# -ge 2 ]] || {
            echo "doctor.sh: --repo に値が必要です" >&2
            exit 2
        }
        repo="$2"
        shift 2
        ;;
    *)
        echo "doctor.sh: 不明な引数: $1" >&2
        exit 2
        ;;
    esac
done

fail=0
ok() { printf '\033[1;32mOK\033[0m   %s\n' "$1"; }
ng() { printf '\033[1;31mNG\033[0m   %s\n' "$1"; fail=1; }
warn() { printf '\033[1;33mWARN\033[0m %s\n' "$1"; }

root="${EVAL_SANDBOX_ROOT:-}"
if [[ -z "$root" ]]; then
    ng "EVAL_SANDBOX_ROOT が無い。<root>/with-env の中で実行してください"
    exit 1
fi

under() { [[ "$1" == "$root" || "$1" == "$root"/* ]]; }
check_under() { # <name> <path>
    if [[ -n "$2" ]] && under "$2"; then ok "$1 が隔離フォルダの下: $2"; else ng "$1 が隔離フォルダの外: ${2:-（未設定）}"; fi
}
check_under HOME "${HOME:-}"
check_under XDG_CONFIG_HOME "${XDG_CONFIG_HOME:-}"
check_under CLAUDE_CONFIG_DIR "${CLAUDE_CONFIG_DIR:-}"
check_under PI_CODING_AGENT_DIR "${PI_CODING_AGENT_DIR:-}"
check_under GH_CONFIG_DIR "${GH_CONFIG_DIR:-}"
check_under TMPDIR "${TMPDIR:-}"
check_under GIT_CONFIG_GLOBAL "${GIT_CONFIG_GLOBAL:-}"

# リンクの先が、隔離フォルダの dotfiles の中にある（ユーザーの ~/dotfiles を指していない）
for l in "$HOME/.claude/CLAUDE.md" "$HOME/.claude/skills" "$HOME/.claude/agents" "$HOME/.claude/hooks" \
    "$HOME/.omp/agent/config.yml" "$HOME/.omp/agent/RULES.md" "$HOME/.omp/agent/WATCHDOG.md" "$HOME/.omp/agent/agents" \
    "$HOME/.omp/agent/extensions" "$HOME/.omp/agent/skills"; do
    if [[ ! -L "$l" ]]; then
        ng "リンクが無い: $l"
    elif [[ ! -e "$l" ]]; then
        ng "リンク切れ: $l"
    else
        real="$(cd "$(dirname "$l")" && cd "$(dirname "$(readlink "$l")")" 2>/dev/null && pwd -P)/$(basename "$(readlink "$l")")"
        if [[ "$real" == "$root/dotfiles/"* ]]; then ok "リンク: ${l#"$HOME"/}"; else ng "リンク先が隔離フォルダの dotfiles の外: $l -> $real"; fi
    fi
done
[[ -f "$HOME/.claude/settings.json" ]] && ok "settings.json がある" || ng "settings.json が無い"
if jq -e '(.env // {}) | has("CLAUDE_CODE_ENABLE_TELEMETRY") or has("OTEL_LOG_USER_PROMPTS")' "$HOME/.claude/settings.json" >/dev/null 2>&1; then
    ng "settings.json にテレメトリの設定が残っている"
else
    ok "settings.json にテレメトリの設定が無い"
fi
[[ ! -e "$HOME/.mcp.json" && ! -e "$HOME/.omp/agent/mcp.json" ]] && ok "MCP の設定を置いていない" || ng "MCP の設定がある（supabase などに繋がる恐れ）"

# 課金・認証
leaked=""
for v in ANTHROPIC_API_KEY ANTHROPIC_AUTH_TOKEN OPENAI_API_KEY GEMINI_API_KEY OPENROUTER_API_KEY GITHUB_TOKEN SSH_AUTH_SOCK GIT_SSH_COMMAND; do
    [[ -z "${!v:-}" ]] || leaked="$leaked $v"
done
[[ -z "$leaked" ]] && ok "API キー・ssh エージェント・GITHUB_TOKEN が環境に無い" || ng "環境に残っている:${leaked}"
if [[ -e "$GH_CONFIG_DIR/hosts.yml" ]]; then ng "gh のログイン情報が隔離フォルダに在る（$GH_CONFIG_DIR/hosts.yml）。トークンは GH_TOKEN だけにする"; else ok "gh のログイン情報（hosts.yml）が無い"; fi

# トークン
if [[ -z "${GH_TOKEN:-}" ]]; then
    warn "GH_TOKEN が無い（EVAL_GH_TOKEN か ${root}/gh-token が必要。dry には要らない）"
else
    if [[ -f "$root/gh-token" ]]; then
        mode="$(ls -l "$root/gh-token" | cut -c1-10)"
        [[ "$mode" == "-rw-------" ]] && ok "gh-token のモードは 600" || ng "gh-token のモードが ${mode}（chmod 600 にしてください）"
    fi
    ok "GH_TOKEN がある（値は表示しない）"
    # 読み取り専用の API で、試験用 repo に届くこと・ほかの repo に届かないことを確かめる
    if command -v gh >/dev/null; then
        if gh api "repos/${repo}" --jq '.full_name' >/dev/null 2>&1; then ok "試験用 repo ${repo} を読める"; else ng "試験用 repo ${repo} を読めない（トークンの対象 repo と権限を確認）"; fi
        if gh api "repos/ousiass/dotfiles" --jq '.permissions.push // false' 2>/dev/null | grep -qx true; then
            ng "トークンが ousiass/dotfiles に書き込める。試験用 repo だけに絞った fine-grained トークンにしてください"
        else
            ok "ousiass/dotfiles には書き込めない"
        fi
    else
        warn "gh が PATH に無い。トークンの到達範囲は確かめていない"
    fi
fi

exit "$fail"
