#!/usr/bin/env bash
#
# reset-tools.sh
#
# install.sh で導入する各種ツールを一括削除し、install.sh で再インストール
# する検証用スクリプト。新マシンの状態を再現したい時に便利。
#
# 削除対象:
#   - uv, bun (グローバルパッケージ含む: codex, gemini, wrangler, netlify-cli, pm2 も)
#   - Codex CLI standalone package (~/.codex/packages/standalone, ~/.local/bin/codex)
#   - lazygit (~/.local/bin/lazygit)
#   - rustup / cargo
#   - fnm + fnm 経由の Node 全バージョン
#   - Go (Linux のみ /usr/local/go、要 sudo)
#   - Claude Code (~/.local/share/claude, ~/.local/bin/claude)
#
# 削除しないもの:
#   - fish, tmux, neovim, git, curl 等のシステムパッケージ
#   - ~/.env, ~/.claude のデータ, ~/.mcp.json, dotfiles 自身
#   - シンボリックリンク (~/.config/{nvim,tmux,fish,gh-dash} 等)
#
# 使い方:
#   bash ~/dotfiles/reset-tools.sh

set -euo pipefail

log()  { printf '\033[1;34m[reset]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; }

DOTFILES_DIR="$HOME/dotfiles"

# ------------------------------------------------------------------
# Agent セッション中は実行しない
# ------------------------------------------------------------------
if [[ -n "${CLAUDECODE:-}" ]]; then
    err "Claude Code セッション中はこのスクリプトを実行できません。"
    err "claude バイナリを削除すると現セッションが壊れます。"
    err "Claude Code を終了してからターミナルで実行してください。"
    exit 1
fi

if [[ -n "${CODEX_CI:-}" || -n "${CODEX_THREAD_ID:-}" ]]; then
    err "Codex セッション中はこのスクリプトを実行できません。"
    err "codex バイナリを削除・更新すると現セッションが壊れます。"
    err "Codex を終了してからターミナルで実行してください。"
    exit 1
fi

# ------------------------------------------------------------------
# 確認プロンプト
# ------------------------------------------------------------------
cat <<'EOF'

==================================================================
以下のツールを削除して install.sh で再インストールします:

  - uv
  - bun (グローバルパッケージ含む: codex, gemini, wrangler, netlify-cli, pm2)
  - Codex CLI standalone package (~/.codex/packages/standalone, ~/.local/bin/codex)
  - lazygit (~/.local/bin/lazygit)
  - rustup / cargo
  - fnm および fnm 経由でインストールした Node 全バージョン
  - Go (Linux のみ, /usr/local/go)
  - Claude Code

削除しないもの:
  - fish/tmux/neovim/git 等のシステムパッケージ
  - ~/.env
  - ~/.claude のデータ
  - dotfiles 配下のシンボリックリンク

==================================================================
EOF

read -rp "続行しますか？ [y/N] " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log "キャンセルしました"
    exit 0
fi

# ------------------------------------------------------------------
# 削除
# ------------------------------------------------------------------
log "uv 削除"
rm -f "$HOME/.local/bin/uv" "$HOME/.local/bin/uvx"

log "bun 削除（グローバルパッケージ codex/gemini も含む）"
rm -rf "$HOME/.bun"

log "Codex CLI standalone package 削除"
rm -f "$HOME/.local/bin/codex"
rm -rf "$HOME/.codex/packages/standalone"

log "lazygit 削除"
rm -f "$HOME/.local/bin/lazygit"

log "rustup / cargo 削除"
if command -v rustup >/dev/null 2>&1; then
    rustup self uninstall -y || true
fi
rm -rf "$HOME/.cargo" "$HOME/.rustup"

log "fnm 削除"
rm -rf "$HOME/.local/share/fnm"
rm -rf "$HOME/.local/state/fnm_multishells"
rm -rf "/run/user/$(id -u)/fnm_multishells" 2>/dev/null || true

log "Claude Code 削除"
rm -rf "$HOME/.local/share/claude" "$HOME/.local/bin/claude"

if [[ "$(uname -s)" == "Linux" ]]; then
    if [[ -d /usr/local/go ]]; then
        log "Go 削除 (/usr/local/go) — sudo パスワードが必要"
        sudo rm -rf /usr/local/go
    else
        log "Go (/usr/local/go) は無し、スキップ"
    fi
fi

log "削除完了"

# ------------------------------------------------------------------
# install.sh 実行
# ------------------------------------------------------------------
log "install.sh で再インストール開始"
cd "$DOTFILES_DIR"
./install.sh

echo
log "リセット & 再インストール完了"
