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

# check-issue-queue.sh が同じ状況を喋る場合はこちらは黙る（2 本が同時に同じことを
# 言うと停止 1 回あたりの context 消費が倍になる）。停止のブロック自体は向こうが行う。
if [[ -f "$DIR/queue.txt" && -s "$DIR/queue.txt" ]]; then
  exit 0
fi

# 鮮度 OK ∧ phase != terminal → 停止をブロック
# メッセージは 1 行に抑える（停止のたびに context に積まれる）。
# `.iteration` と `.last_counts` は sweep 系のスキーマに存在しないので出力しない
# （前者は常に 0、後者は常に {} だった）。
SKILL=$(jq -r '.skill // "sweep"' "$STATE" 2>/dev/null)
REMAINING=$(jq -r '.queue_remaining // "-"' "$STATE" 2>/dev/null)

echo "${SKILL}: phase=${PHASE}（残 ${REMAINING}）で terminal 未到達。閾値到達まで継続するか termination_reason を設定して terminal 化してから停止（推定 terminal 禁止）。待つだけなら停止せず \`sleep 60\` を 1 コマンド実行して再確認する。" >&2
exit 2
