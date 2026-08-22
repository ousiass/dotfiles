#!/usr/bin/env bash
# sweep 系スキル（issue-sweep / refine / refine-git / refine-sweep）の Stop Hook。
# .sweep/state.json が "phase=terminal" に到達していない間は exit 2 で停止をブロックし、
# stderr に続行メッセージを出す。
# lock が stale または存在しない場合は exit 0（停止許可、クラッシュ放置と判定）。

set -u

DIR="${CLAUDE_PROJECT_DIR:-$PWD}/.sweep"
STATE="$DIR/state.json"
LOCK="$DIR/lock"
STALE_THRESHOLD=7200  # 2時間 (sec)

# state.json なし → sweep は走っていない。停止許可
[[ -f "$STATE" ]] || exit 0

PHASE=$(jq -r '.phase // empty' "$STATE" 2>/dev/null)
[[ "$PHASE" == "terminal" ]] && exit 0

# state.json はあるが terminal でない → lock の鮮度で「本当に走っているか」を判定
[[ -f "$LOCK" ]] || exit 0  # lock なし = クラッシュ放置と判定、停止許可

lock_ts=$(cut -d: -f2 "$LOCK" 2>/dev/null)
if [[ -z "$lock_ts" || ! "$lock_ts" =~ ^[0-9]+$ ]]; then
  exit 0  # 不正な lock も stale 扱い
fi

now=$(date +%s)
age=$((now - lock_ts))
if (( age > STALE_THRESHOLD )); then
  exit 0  # 2時間以上更新なし → クラッシュ放置と判定、停止許可
fi

# 鮮度 OK ∧ phase != terminal → 停止をブロック
SKILL=$(jq -r '.skill // "sweep"' "$STATE" 2>/dev/null)
ITER=$(jq -r '.iteration // 0' "$STATE" 2>/dev/null)
COUNTS=$(jq -c '.last_counts // {}' "$STATE" 2>/dev/null)
REMAINING=$(jq -r '.queue_remaining // "-"' "$STATE" 2>/dev/null)

echo "${SKILL}: .sweep/state.json は phase=${PHASE}（iter=${ITER}, queue_remaining=${REMAINING}, last_counts=${COUNTS}）で terminal に到達していません。" >&2
echo "閾値到達まで review→fix を反復するか、状況に応じて termination_reason を設定して phase=terminal にしてから停止してください。" >&2
echo "（推定で terminal にするのは禁止。失敗で打ち切る場合も termination_reason を設定してレポートを生成すること）" >&2
exit 2
