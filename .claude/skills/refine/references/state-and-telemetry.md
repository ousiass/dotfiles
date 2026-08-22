# refine 系 状態管理とテレメトリ

`refine` / `refine-git` が共有する `.sweep/state.json` と `.sweep/refine-metrics.jsonl` の仕様。

## `.sweep/state.json`

sweep 系スキル共通の進行状態ファイル。**場所は常に `$SWEEP_DIR`（メインリポジトリ側。`common-setup.md` 手順3 参照）**。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**最終反復のレビュー結果を確認せず推定で `phase=terminal` にしてはならない。**

`OWNS_STATE=false`（呼び出し元の sweep が state.json を所有している）のときは、このファイルへの書き込みをすべてスキップしてテレメトリのみ追記する（`common-setup.md` 手順4 のガード）。

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
  "termination_reason": null | "thresholds_met" | "iter_limit" | "no_progress" | "agent_failed" | "merge_failed" | "ci_gave_up" | "atomic_design_required" | "aborted",
  "pr_number": <N>
}
```

**更新タイミング:**
- フェーズ1 開始時に `phase=iterating, iteration=0` で初期化（`common-setup.md` 参照）
- 各反復終了時（テレメトリ追記直後）に `iteration += 1`、`last_counts` を最新の review 集計結果で上書き、`updated_at` 更新。`last_counts` は 2-3 の `no_progress` 判定に使うので必ず更新する
- フェーズ3 で `phase=terminal` と `termination_reason` をセット

**監査証跡は `$SWEEP_DIR/refine-metrics.jsonl` 一本に集約する。** state.json に行番号を写す `evidence` 配列は廃止した（Stop Hook は判定に使っておらず、同じ情報を 3 箇所に持つだけだった）。

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
  >> "$SWEEP_DIR/refine-metrics.jsonl"

# state.json を更新（OWNS_STATE=true のときのみ）
[[ "$OWNS_STATE" == "true" ]] && jq --argjson iter "$iter" \
   --argjson c "$(echo "$findings" | jq '.critical | length')" \
   --argjson m "$(echo "$findings" | jq '.major | length')" \
   --argjson mn "$(echo "$findings" | jq '.minor | length')" \
   --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.iteration = $iter
    | .last_counts = {critical:$c, major:$m, minor:$mn}
    | .updated_at = $now' \
   "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
```

## 消費側への注意

`$SWEEP_DIR/refine-metrics.jsonl` は `refine` と `refine-git` の両方が書き込む。行を集計する側（`issue-sweep` のレポート生成等）は `source` で判別すること:

```bash
# refine 系の行だけを取る
jq 'select(.source | startswith("refine"))' "$SWEEP_DIR/refine-metrics.jsonl"

# refine 系の行を除外する
jq 'select(.source | startswith("refine") | not)' "$SWEEP_DIR/refine-metrics.jsonl"
```

**worktree 内で走っても `$SWEEP_DIR` はメインリポジトリを指す**ので、worktree 削除でテレメトリが消えることはない（以前は消えていて、`issue-sweep` のレポートの refine セクションが常に空だった）。
