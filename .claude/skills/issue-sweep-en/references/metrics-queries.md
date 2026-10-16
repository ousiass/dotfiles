# Metrics aggregation queries

**Read this file only when aggregating duration and failure breakdown for the completion report.** The append specification for `$SWEEP_DIR/metrics.jsonl` is in the SKILL.md body.

```bash
# Duration stats for the latest sweep
jq -s 'group_by(.skill) | map({skill: .[0].skill, avg: (map(.duration_sec) | add/length | floor), n: length})' "$SWEEP_DIR/metrics.jsonl"

# Failure rate
jq -s '[.[] | select(.status != "merged")] | length' "$SWEEP_DIR/metrics.jsonl"

# CI respawn heatmap
jq -s 'map(select(.ci_respawns > 0)) | group_by(.ci_respawns) | map({respawns: .[0].ci_respawns, n: length})' "$SWEEP_DIR/metrics.jsonl"
```
