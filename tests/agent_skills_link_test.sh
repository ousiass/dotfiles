#!/usr/bin/env bash
# lib/tools/agent_skills.sh（link_local_agent_skills）の回帰テスト。フレームワークは使わず bash だけで完結させる。
#
#   ./tests/agent_skills_link_test.sh
#
# dotfiles の .agents/skills/<name>（取り込み済みの外部 skill の実体）が、Codex（~/.agents/skills）・
# Claude Code と omp（~/.claude/skills）・Cursor（~/.cursor/skills）から実体 1 か所に解決されることを確かめる。
# HOME は一時ディレクトリに差し替え、本物の ~/.agents ~/.claude ~/.codex には触れない。
# lib/ は一時ディレクトリの偽 dotfiles にコピーする（sync_agent_skills_gitignore が書くのは偽側の .claude）。
# PATH は許可リストだけにし、bunx が無い環境でもリンクできることも見る。
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

tmp="$(cd "$(mktemp -d)" && pwd -P)"
trap 'rm -rf "$tmp"' EXIT

stubs="$tmp/bin"
mkdir -p "$stubs"
for c in awk basename cat chmod cmp date dirname grep id ln mkdir mktemp mv readlink rm sed tr uname; do
    if command -v "$c" >/dev/null 2>&1; then ln -sf "$(command -v "$c")" "$stubs/$c"; fi
done

# 偽 dotfiles: lib はコピー、取り込み済み skill の実体は本物の .agents を指す
fake="$tmp/dotfiles"
mkdir -p "$fake/.claude/skills"
cp -R "$DOTFILES_DIR/lib" "$fake/lib"
ln -s "$DOTFILES_DIR/.agents" "$fake/.agents"

driver="$tmp/driver.sh"
cat >"$driver" <<'EOF'
set -euo pipefail
export DOTFILES_DIR
CONFIG_DIR="$HOME/.config"
TIMESTAMP=test
OS=linux
. "$DOTFILES_DIR/lib/load.sh"
"$@"
EOF

# new_home <名前> : link_claude 済みの HOME（~/.claude → 偽 dotfiles の .claude）を作る
new_home() {
    local h="$tmp/$1"
    mkdir -p "$h"
    ln -s "$fake/.claude" "$h/.claude"
    printf '%s' "$h"
}

# run <HOME> <DOTFILES_DIR> <関数名> : 終了コードを $rc に入れる（出力は捨てる）
run() {
    env PATH="$stubs" HOME="$1" DOTFILES_DIR="$2" "$BASH" "$driver" "$3" >/dev/null 2>&1
    rc=$?
}

phys() { (cd -P "$1" 2>/dev/null && pwd -P); }

real_unslop="$(phys "$DOTFILES_DIR/.agents/skills/unslop")"
check_true "取り込み済みの実体がある（.agents/skills/unslop/SKILL.md）" test -f "$DOTFILES_DIR/.agents/skills/unslop/SKILL.md"
check_match "SKILL.md の name が unslop" "name: unslop" "$(cat "$DOTFILES_DIR/.agents/skills/unslop/SKILL.md")"

# --- 初回: すべての読み場所が実体 1 か所に解決される -----------------------------------
home="$(new_home h1)"
run "$home" "$fake" link_local_agent_skills
check_eq "初回は成功する" "0" "$rc"
check_eq "HOME/.agents/skills/unslop は dotfiles の実体への symlink" "$fake/.agents/skills/unslop" "$(readlink "$home/.agents/skills/unslop")"
for where in .agents .claude .codex .cursor; do
    check_eq "HOME/$where/skills/unslop は実体に解決される" "$real_unslop" "$(phys "$home/$where/skills/unslop")"
    check_true "HOME/$where/skills/unslop/SKILL.md を読める" test -r "$home/$where/skills/unslop/SKILL.md"
    check_true "HOME/$where/skills/unslop は symlink（実体の二重管理をしない）" test -L "$home/$where/skills/unslop"
done
check_match "偽 dotfiles の .claude/skills/.gitignore に /unslop が載る（symlink を git に入れない）" "/unslop" \
    "$(cat "$fake/.claude/skills/.gitignore" 2>/dev/null)"

# --- 2 回目: 何も変えず成功する ---------------------------------------------------------
run "$home" "$fake" link_local_agent_skills
check_eq "2 回目も成功する" "0" "$rc"
check_eq "2 回目も実体は同じ" "$fake/.agents/skills/unslop" "$(readlink "$home/.agents/skills/unslop")"
check_eq "バックアップを作らない" "0" "$(find "$home/.agents/skills" "$fake/.claude/skills" -name '*.bak.*' | wc -l | tr -d ' ')"

# --- 自作 skill（実ディレクトリ）は上書きしない -------------------------------------------
home="$(new_home h2)"
mkdir -p "$home/.codex/skills/unslop"
echo mine >"$home/.codex/skills/unslop/SKILL.md"
run "$home" "$fake" link_local_agent_skills
check_eq "自作の ~/.codex/skills/unslop は残る" "mine" "$(cat "$home/.codex/skills/unslop/SKILL.md")"
check_eq "自作が衝突しても他の読み場所はリンクされる" "$real_unslop" "$(phys "$home/.claude/skills/unslop")"

# --- 実体の置き場が無い dotfiles では何もしない -------------------------------------------
home="$(new_home h3)"
bare="$tmp/bare"
mkdir -p "$bare"
cp -R "$DOTFILES_DIR/lib" "$bare/lib"
run "$home" "$bare" link_local_agent_skills
check_eq ".agents が無ければ成功して何もしない" "0" "$rc"
check_true ".agents が無ければ ~/.agents を作らない" test ! -e "$home/.agents"

if [[ "$fail" -ne 0 ]]; then
    echo
    echo "失敗あり"
    exit 1
fi
echo
echo "すべて成功"
