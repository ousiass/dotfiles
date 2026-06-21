#!/usr/bin/env bash
# issue-sweep スキル用の Stop Hook。
# キューに未処理 Issue が残っており、かつ lock が新鮮（heartbeat 2時間以内）なら
# exit 2 で停止をブロックし stderr に続行メッセージを出す。
# lock が stale または存在しない場合は exit 0（停止を許可）。

set -u

DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.claude"
QUEUE="$DIR/issue-queue.txt"
LOCK="$DIR/issue-queue.lock"
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

# 鮮度 OK → sweep アクティブ。停止をブロック
NEXT=$(head -n1 "$QUEUE")
REMAINING=$(wc -l <"$QUEUE" | tr -d ' ')
echo "issue-sweep: 未処理 Issue が ${REMAINING} 件残っています。次は #${NEXT}。/issue-sweep のフェーズ2を続行してください（PR マージまで完了させてから heartbeat 更新→キュー削除）。" >&2
exit 2
