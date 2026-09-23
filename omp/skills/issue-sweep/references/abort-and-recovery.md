# --abort と失敗時のリカバリ

**このファイルは `--abort` 指定時、または処理が失敗したときだけ読めばよい。**

## --abort 処理

引数が `--abort` の場合は以下を実行して終了する（他フェーズに進まない）:

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
rm -f "$SWEEP_DIR/queue.txt" "$SWEEP_DIR/lock" "$SWEEP_DIR/attempts.json"
# state.json があれば terminal 化（履歴を残すため削除しない）
if [[ -f "$SWEEP_DIR/state.json" ]]; then
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.phase = "terminal" | .termination_reason = "aborted" | .updated_at = $now' \
    "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
fi
# 残った worktree の掃除
git worktree prune
```

完了後「sweep を中止しキュー / ロックを削除しました」とユーザーに報告。

## 失敗時の挙動

- **1 バッチの失敗で sweep 全体を止めない。** `attempts.json` が 2 に達したバッチだけ諦め、キューから該当行を消して metrics に `agent_failed` を記録し、残りのバッチを流し続ける
- 諦めたバッチは**必ずキューから消す**。残すと Stop Hook が停止をブロックし続けて sweep が終われない
- 観測時の `CLOSED ∧ merged == false`（手動 close）は 1 回目は agent 再起動、2 回連続でユーザー判断
- キューファイルが壊れた場合は `--abort` で全削除してフェーズ1からやり直す
- **すべてのバッチが諦めに終わった場合も、完了報告フェーズに進んで terminal 化とレポート生成を行う**（`termination_reason = "batch_failed"`）。記録が残らないまま終わるのが最悪
