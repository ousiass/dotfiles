#!/usr/bin/env bash
# issue-sweep スキル用の Stop Hook。
# キューファイルに未処理 Issue が残っていれば exit 2 で停止をブロックし、
# stderr に次の Issue 番号を出力して Claude に続行を促す。

set -u

QUEUE="${CLAUDE_PROJECT_DIR:-$PWD}/.claude/issue-queue.txt"

if [[ -f "$QUEUE" ]] && [[ -s "$QUEUE" ]]; then
  NEXT=$(head -n1 "$QUEUE")
  REMAINING=$(wc -l <"$QUEUE" | tr -d ' ')
  echo "issue-sweep: 未処理 Issue が ${REMAINING} 件残っています。次は #${NEXT}。/issue-sweep のフェーズ2を続行してください（PR マージまで完了させてからキュー先頭を削除）。" >&2
  exit 2
fi

exit 0
