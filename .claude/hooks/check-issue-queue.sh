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

# 鮮度 OK → sweep アクティブ。停止をブロック
NEXT=$(head -n1 "$QUEUE")
REMAINING=$(wc -l <"$QUEUE" | tr -d ' ')
# メッセージは 1 行に抑える。停止のたびに context に積まれるので、長文は sweep 1 本で
# 数十万文字になる（実測: 1 セッション 1 万回ブロック = トランスクリプトの 10%）。
echo "issue-sweep: 未処理 ${REMAINING} 件（次 #${NEXT}）。フェーズ2 を続行。待つだけなら停止せず \`sleep 60\` を 1 コマンド実行して再確認する。" >&2
exit 2
