# --abort と失敗時のリカバリ

**このファイルは `--abort` 指定時、または処理が失敗したときだけ読めばよい。**

## --abort 処理

引数が `--abort` の場合は以下を実行して終了する（他フェーズに進まない）:

```bash
rm -f .sweep/queue.txt .sweep/lock
# state.json があれば terminal 化（履歴を残すため削除しない）
if [[ -f .sweep/state.json ]]; then
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.phase = "terminal" | .termination_reason = "aborted" | .updated_at = $now' \
    .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
fi
```

完了後「sweep を中止しキュー / ロックを削除しました」とユーザーに報告。

## 失敗時の挙動

- サブスキル失敗 / PR 作成失敗 / 直接マージ失敗のいずれも、Issue 番号をキューに残したまま中断し、ロック (`.sweep/lock`) は削除してユーザーに報告する
- ポーリング中の `CLOSED null` は1回目はサブスキル再実行、2回連続でユーザー判断
- キューファイルが壊れた場合は `--abort` で全削除してフェーズ1からやり直す
- 同じ Issue で2回連続して同じエラーが出たらユーザーに判断を仰ぐ（無限ループ防止）
