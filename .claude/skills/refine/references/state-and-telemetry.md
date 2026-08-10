# refine 系 状態管理とテレメトリ

`refine` / `refine-git` が共有する `.sweep/state.json` と `.sweep/refine-metrics.jsonl` の仕様。

## `.sweep/state.json`

sweep 系スキル共通の進行状態ファイル。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**review を再実行せず推定で `phase=terminal` にしてはならない**。terminal 化前に必ず最終 review を走らせ、その出力パスを `evidence` に append する。

**スキーマ:**
```json
{
  "skill": "refine" | "refine-git",
  "started_at": "<ISO8601>",
  "updated_at": "<ISO8601>",
  "phase": "iterating" | "terminal",
  "iteration": <N>,
  "max_iter": <N>,
  "thresholds": {"critical": 0, "major": 0, "minor": <max_minor>},
  "last_counts": {"critical": <N>, "major": <N>, "minor": <N>},
  "evidence": ["<path>", ...],
  "termination_reason": null | "thresholds_met" | "iter_limit" | "agent_failed" | "merge_failed" | "ci_gave_up" | "atomic_design_required" | "aborted",
  "pr_number": <N>
}
```

**更新タイミング:**
- フェーズ1 開始時に `phase=iterating, iteration=0, evidence=[]` で初期化（`common-setup.md` 参照）
- 各反復終了時（テレメトリ追記直後）に `iteration += 1`、`last_counts` を最新の review 集計結果で上書き、`evidence` に当該反復のテレメトリ参照（`.sweep/refine-metrics.jsonl:<行番号>`）を append、`updated_at` 更新
- フェーズ3 で `phase=terminal` と `termination_reason` をセット。**直前に最終 review を走らせ evidence を追加してから terminal 化する**

## 反復ごとのテレメトリ追記 + state.json 更新

```bash
# テレメトリ append（refine / refine-git 共通ファイル。source で区別する）
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg skill "$skill_name" \
  --argjson pr "$pr_number" \
  --argjson iter "$iter" \
  --argjson c "$(echo "$findings" | jq '.critical | length')" \
  --argjson m "$(echo "$findings" | jq '.major | length')" \
  --argjson mn "$(echo "$findings" | jq '.minor | length')" \
  --argjson by_src "$(echo "$findings" | jq '.by_source')" \
  --argjson halt "$HAS_HALT" \
  '{ts:$ts,source:$skill,pr_number:$pr,iter:$iter,critical:$c,major:$m,minor:$mn,by_source:$by_src,halt:$halt}' \
  >> .sweep/refine-metrics.jsonl

# state.json を更新（iteration / last_counts / evidence append）
ev_line=".sweep/refine-metrics.jsonl:$(wc -l < .sweep/refine-metrics.jsonl | tr -d ' ')"
jq --argjson iter "$iter" \
   --argjson c "$(echo "$findings" | jq '.critical | length')" \
   --argjson m "$(echo "$findings" | jq '.major | length')" \
   --argjson mn "$(echo "$findings" | jq '.minor | length')" \
   --arg ev "$ev_line" \
   --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.iteration = $iter
    | .last_counts = {critical:$c, major:$m, minor:$mn}
    | .evidence += [$ev]
    | .updated_at = $now' \
   .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
```

**evidence の append 規則**: 各反復で最低 1 件追加する。空のままフェーズ3 に進まない。

## 消費側への注意

`.sweep/refine-metrics.jsonl` は `refine` と `refine-git` の両方が書き込む。行を集計する側（`issue-sweep` のレポート生成等）は `source` で判別すること:

```bash
# refine 系の行だけを取る
jq 'select(.source | startswith("refine"))' .sweep/refine-metrics.jsonl

# refine 系の行を除外する
jq 'select(.source | startswith("refine") | not)' .sweep/refine-metrics.jsonl
```
