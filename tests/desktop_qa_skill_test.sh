#!/usr/bin/env bash
# desktop-qa スキルの scripts/remo.py（puppet-remo MCP の小さなクライアント）の回帰テスト。
# 本物の puppet-remo には接続しない。tests/fixtures/desktop-qa/fake_remo.py（偽サーバー）を相手にする。
#
#   ./tests/desktop_qa_skill_test.sh
#
# 守るもの:
#   1. 操作権（lease）はセッションに付く。呼び出しごとにセッションを作り直すと、2 回目の入力が
#      lease_held_by_other で落ちる（再現を 2 で確かめる）。remo.py はセッション ID を保存して使い回す。
#   2. トークンの値を標準出力・標準エラー・保存ファイルに出さない（サーバーが返答に含めても伏せる）。
#   3. Host ヘッダー（REMO_HOST）を送る・~/.env 形式のファイルからトークンを読む・SSE の返答を読む。
#   4. セッションが切れたら（404）作り直す。close で操作権を返す。
#   5. shot がスクショを保存し、Pillow があれば --window で切り抜く。
set -uo pipefail

DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REMO="$DOTFILES_DIR/.claude/skills/desktop-qa/scripts/remo.py"
FAKE="$DOTFILES_DIR/tests/fixtures/desktop-qa/fake_remo.py"

fail=0
ok() { printf '\033[1;32mPASS\033[0m %s\n' "$1"; }
ng() { printf '\033[1;31mFAIL\033[0m %s\n' "$1"; fail=1; }

if ! command -v python3 >/dev/null 2>&1; then
    echo "python3 が無い" >&2
    exit 1
fi

TMP="$(mktemp -d)"
TOKEN="tok-$RANDOM$RANDOM-not-a-real-secret"
HOSTHDR="100.94.64.51:8765"
FAKE_PID=""
cleanup() {
    [ -n "$FAKE_PID" ] && kill "$FAKE_PID" 2>/dev/null
    rm -rf "$TMP"
}
trap cleanup EXIT

python3 "$FAKE" "$TMP/port" "$TOKEN" "$HOSTHDR" &
FAKE_PID=$!
# 準備完了の合図（ポートファイル）を上限つきで待つ
for _ in $(seq 1 100); do
    [ -s "$TMP/port" ] && break
    kill -0 "$FAKE_PID" 2>/dev/null || break
    sleep 0.1
done
if [ ! -s "$TMP/port" ]; then
    echo "偽サーバーが起動しない" >&2
    exit 1
fi
PORT="$(cat "$TMP/port")"

export REMO_URL="http://127.0.0.1:$PORT/mcp"
export REMO_HOST="$HOSTHDR"
export REMO_STATE="$TMP/state.json"
export PUPPET_REMO_TOKEN="$TOKEN"
export REMO_ENV="$TMP/no-such-env"

# remo を動かし、標準出力・標準エラー・終了コードを $TMP/out・$TMP/err・$rc に残す
run() {
    python3 "$REMO" "$@" >"$TMP/out" 2>"$TMP/err"
    rc=$?
    cat "$TMP/out" "$TMP/err" >>"$TMP/all"
}
lease_state() { python3 "$REMO" call _state | python3 -c 'import json,sys; d=json.load(sys.stdin); print("held" if d["holder"] else "idle")'; }

# --- 3. 道具の一覧（JSON の返答）と SSE の返答 ---
run tools
if [ "$rc" -eq 0 ] && grep -q '^left_click	fake left_click$' "$TMP/out"; then
    ok "tools: 名前と説明の 1 行目"
else
    ng "tools が一覧を出さない (rc=$rc): $(cat "$TMP/out" "$TMP/err")"
fi

# --- 1. 同じセッションを使い回すので、続けて入力しても操作権を失わない ---
run call left_click '{"x":1,"y":2}'
rc1=$rc
run call type '{"text":"abc"}'
if [ "$rc1" -eq 0 ] && [ "$rc" -eq 0 ] && grep -q '"tool": "type"' "$TMP/out"; then
    ok "呼び出しをまたいで操作権を保つ（セッションの使い回し）"
else
    ng "2 回目の入力が落ちた (rc1=$rc1 rc=$rc): $(cat "$TMP/err")"
fi

# --- 1 の再現: セッションの保存を消す（＝呼び出しごとに作り直す）と lease_held_by_other になる ---
rm -f "$REMO_STATE"
run call key '{"keys":"enter"}'
if [ "$rc" -eq 1 ] && grep -q 'another session holds' "$TMP/err"; then
    ok "再現: セッションを作り直すと 2 回目の入力が lease_held_by_other で落ちる（終了コード 1）"
else
    ng "セッションを作り直したのに落ちない (rc=$rc): $(cat "$TMP/out" "$TMP/err")"
fi

# --- 4. サーバー側でセッションが消えたら（404）作り直して続ける ---
run call _forget_sessions
run call left_click '{"x":3,"y":4}'
if [ "$rc" -eq 0 ] && grep -q '作り直した' "$TMP/err"; then
    ok "切れたセッション（404）を作り直す"
else
    ng "切れたセッションから戻らない (rc=$rc): $(cat "$TMP/err")"
fi

# --- 2. 返答にトークンが含まれても伏せる ---
run call echo_auth
if [ "$rc" -eq 0 ] && grep -q 'Bearer \*\*\*' "$TMP/out"; then
    ok "返答に含まれたトークンを *** に伏せる"
else
    ng "トークンが伏せられていない (rc=$rc)"
fi

# --- 2. 保存ファイルは 0600 で、トークンを含まない ---
mode="$(python3 -c 'import os,stat,sys; print(oct(stat.S_IMODE(os.stat(sys.argv[1]).st_mode)))' "$REMO_STATE")"
if [ "$mode" = "0o600" ] && ! grep -qF "$TOKEN" "$REMO_STATE"; then
    ok "セッションの保存ファイルは 0600・トークンなし"
else
    ng "保存ファイルの権限 ${mode}、またはトークンを含む"
fi

# --- 5. shot: そのまま保存 / --window で切り抜き ---
run shot "$TMP/shots/full.png"
if [ "$rc" -eq 0 ] && [ "$(head -c 8 "$TMP/shots/full.png" | od -An -tx1 | tr -d ' \n')" = "89504e470d0a1a0a" ]; then
    ok "shot: PNG を保存（保存先のフォルダーも作る）"
else
    ng "shot が PNG を保存しない (rc=$rc): $(cat "$TMP/err")"
fi
if python3 -c 'import PIL' 2>/dev/null; then
    run shot "$TMP/shots/win.png" --window 42 --zoom 3
    px="$(python3 -c 'from PIL import Image; import sys; im=Image.open(sys.argv[1]).convert("RGB"); print(im.size, im.getpixel((0,0)))' "$TMP/shots/win.png" 2>/dev/null)"
    if [ "$rc" -eq 0 ] && [ "$px" = "(3, 3) (0, 0, 255)" ]; then
        ok "shot --window: ウィンドウの矩形だけを切り抜いて拡大"
    else
        ng "shot --window の切り抜きが違う (rc=$rc px=$px): $(cat "$TMP/err")"
    fi
else
    echo "SKIP shot --window（Pillow が無い）"
fi

# --- 4. close で操作権を返す ---
run close
state="$(lease_state)"
if [ "$rc" -eq 0 ] && [ "$state" = "idle" ]; then
    ok "close で操作権を返す"
else
    ng "close 後も操作権が残る (rc=$rc state=$state)"
fi
python3 "$REMO" close >/dev/null 2>&1

# --- 3. ~/.env 形式のファイルからトークンを読む ---
printf '# comment\nOTHER=1\nexport PUPPET_REMO_TOKEN="%s"\n' "$TOKEN" >"$TMP/env"
PUPPET_REMO_TOKEN="" REMO_ENV="$TMP/env" python3 "$REMO" call get_control_status >"$TMP/out" 2>"$TMP/err"
rc=$?
cat "$TMP/out" "$TMP/err" >>"$TMP/all"
if [ "$rc" -eq 0 ] && grep -q '"state"' "$TMP/out"; then
    ok "REMO_ENV（~/.env 形式）からトークンを読む"
else
    ng "env ファイルからトークンを読めない (rc=$rc): $(cat "$TMP/err")"
fi
PUPPET_REMO_TOKEN="" REMO_ENV="$TMP/env" python3 "$REMO" close >/dev/null 2>&1

# --- 3. Host ヘッダーが違うと 403（終了コード 2） ---
REMO_HOST="127.0.0.1:$PORT" python3 "$REMO" call get_control_status >"$TMP/out" 2>"$TMP/err"
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'HTTP 403' "$TMP/err"; then
    ok "REMO_HOST を Host ヘッダーに使う（違えば 403 で終了コード 2）"
else
    ng "Host ヘッダーの扱いが違う (rc=$rc): $(cat "$TMP/err")"
fi

# --- 2. トークン違い（401）でも、どちらの値も出さない ---
rm -f "$REMO_STATE"
WRONG="wrong-$RANDOM$RANDOM"
PUPPET_REMO_TOKEN="$WRONG" python3 "$REMO" call get_control_status >"$TMP/out" 2>"$TMP/err"
rc=$?
if [ "$rc" -eq 2 ] && grep -q '401' "$TMP/err" && ! grep -qF -e "$WRONG" -e "$TOKEN" "$TMP/out" "$TMP/err"; then
    ok "401 は終了コード 2、トークンを出さない"
else
    ng "401 の扱いが違うか、トークンが出た (rc=$rc)"
fi

# --- 2. トークンが無ければ終了コード 2 ---
PUPPET_REMO_TOKEN="" python3 "$REMO" tools >"$TMP/out" 2>"$TMP/err"
rc=$?
if [ "$rc" -eq 2 ] && grep -q 'PUPPET_REMO_TOKEN が見つからない' "$TMP/err"; then
    ok "トークンが無ければ終了コード 2"
else
    ng "トークン無しの扱いが違う (rc=$rc): $(cat "$TMP/err")"
fi

# --- 2. ここまでの全出力にトークンが出ていない ---
if ! grep -qF "$TOKEN" "$TMP/all"; then
    ok "全出力にトークンの値が出ていない"
else
    ng "どこかの出力にトークンの値が出た"
fi

# --- スキルの参照先が揃っている ---
SKILL_DIR="$DOTFILES_DIR/.claude/skills/desktop-qa"
missing=""
for rel in $(grep -oE '\((references|templates)/[^)]+\.md\)' "$SKILL_DIR/SKILL.md" | tr -d '()' | sort -u); do
    [ -f "$SKILL_DIR/$rel" ] || missing="$missing $rel"
done
if [ -z "$missing" ]; then
    ok "SKILL.md が参照するファイルがある"
else
    ng "SKILL.md の参照先が無い:$missing"
fi

exit "$fail"
