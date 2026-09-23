#!/usr/bin/env bash
# issue-sweep スキル用の Stop Hook。
# キューに未処理 Issue が残っており、かつ lock が新鮮（heartbeat 2時間以内）なら
# exit 2 で停止をブロックし stderr に続行メッセージを出す。
# lock が stale または存在しない場合は exit 0（停止を許可）。

set -u

DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.sweep"
QUEUE="$DIR/queue.txt"
LOCK="$DIR/lock"
STALE_THRESHOLD=7200  # 2時間 (sec)

# キューなし / 空 → 通常停止 OK
[[ -f "$QUEUE" && -s "$QUEUE" ]] || exit 0

# lock なし → sweep は走っていない（キューだけ残った異常状態）。停止許可
[[ -f "$LOCK" ]] || exit 0

# lock の鮮度判定
lock_ts=$(cut -d: -f2 "$LOCK" 2>/dev/null)
if [[ -z "$lock_ts" || ! "$lock_ts" =~ ^[0-9]+$ ]]; then
  exit 0  # 不正な lock は stale 扱い
fi

now=$(date +%s)
age=$((now - lock_ts))
if (( age > STALE_THRESHOLD )); then
  # 2時間以上更新なし → クラッシュ放置と判定して停止許可
  exit 0
fi

# lock の所有者が自分かを見る。
# lock は sweep を回しているセッションの PID を持つ。同じリポジトリで別の作業を
# しているだけのセッションまで止めると、そちらは引き取ることも解除することもできず
# hook と無限に往復する（引き取れば同じ Issue を二重に実装して PR が衝突する）。
# hook は sweep セッションの子プロセスとして起動するので、自分の祖先に lock の PID が
# 居るかどうかで所有者を判定できる。
lock_pid=$(cut -d: -f1 "$LOCK" 2>/dev/null)
if [[ "$lock_pid" =~ ^[0-9]+$ ]]; then
  owner=0
  p=$$
  while [[ "$p" -gt 1 ]]; do
    if [[ "$p" == "$lock_pid" ]]; then
      owner=1
      break
    fi
    p=$(awk '/^PPid:/ {print $2}' "/proc/$p/status" 2>/dev/null)
    [[ -n "$p" ]] || break
  done
  # 所有者でない かつ lock の PID が生きている → 別セッションの sweep。停止許可
  if (( owner == 0 )) && kill -0 "$lock_pid" 2>/dev/null; then
    exit 0
  fi
fi

# 鮮度 OK → sweep アクティブ。停止をブロック
NEXT=$(head -n1 "$QUEUE")
REMAINING=$(wc -l <"$QUEUE" | tr -d ' ')
# メッセージは 1 行に抑える。停止のたびに context に積まれるので、長文は sweep 1 本で
# 数十万文字になる（実測: 1 セッション 1 万回ブロック = トランスクリプトの 10%）。
echo "issue-sweep: 未処理 ${REMAINING} 件（次 #${NEXT}）。フェーズ2 を続行。待つだけなら停止せず \`sleep 60\` を 1 コマンド実行して再確認する。" >&2
exit 2
