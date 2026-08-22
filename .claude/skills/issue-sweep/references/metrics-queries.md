# メトリクス集計クエリ

**このファイルはフェーズ3-1 で所要時間・失敗内訳を集計するときだけ読めばよい。** `$SWEEP_DIR/metrics.jsonl` への追記仕様は SKILL.md 本体にある。

```bash
# 直近 sweep の所要時間統計
jq -s 'group_by(.skill) | map({skill: .[0].skill, avg: (map(.duration_sec) | add/length | floor), n: length})' "$SWEEP_DIR/metrics.jsonl"

# 失敗率
jq -s '[.[] | select(.status != "merged")] | length' "$SWEEP_DIR/metrics.jsonl"

# CI respawn ヒートマップ
jq -s 'map(select(.ci_respawns > 0)) | group_by(.ci_respawns) | map({respawns: .[0].ci_respawns, n: length})' "$SWEEP_DIR/metrics.jsonl"
```
