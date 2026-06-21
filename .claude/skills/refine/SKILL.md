---
name: refine
description: review agent を反復起動し critical/major=0 ∧ minor≤閾値 になるまで自動修正→再レビューを繰り返す。
user-invocable: true
---

# refine

review → 修正 → 再 review を回し、PR をレビュー観点で「軽微指摘のみ」状態まで持っていくスキル。issue-sweep の各サブスキルが内部で持つ改善サイクルとは独立し、**既存ブランチ / PR に追加で適用**できる。

## 引数

- `/refine` — 現在のブランチ / PR を対象
- `/refine #<PR番号>` — 特定 PR を対象
- `/refine --max-minor <N>` — minor 指摘の上限（デフォルト 5）
- `/refine --max-iter <N>` — レビューループ反復上限（デフォルト 10）

## 前提

- `git`, `gh` CLI 認証済み
- 対象 PR / ブランチが checkout 可能
- `.sweep/` ディレクトリへの書き込み権限（テレメトリ用）

## フェーズ1: ターゲット特定

1. 引数が PR 番号: `gh pr view <n> --json number,headRefName,baseRefName,url`
2. 引数なし: 現ブランチで `gh pr view --json ...` を試す。なければ現ブランチを直接対象に
3. worktree が必要なら `references/worktree-setup.md`（impl-wt と共通） に従って作る
4. `start_ts=$(date +%s)`, `iter=0`, `max_minor=5`, `max_iter=10` を初期化

## フェーズ2: review → 修正ループ

各反復で `Agent(subagent_type=claude)` を起動。**メインスレッドはコードに触れない**。

### 2-1. review agent

```
Agent({
  description: "Refine iteration <iter+1> review",
  subagent_type: "claude",
  prompt: """
PR #<n>（branch: <branch>）をレビューしてください。

タスク:
1. `git checkout <branch>` で対象に切り替える
2. review エージェント (Skill ツール経由ではなく直接 Agent(review)) を起動して全変更をレビュー
3. 指摘を以下の severity で分類:
   - critical: バグ・セキュリティ問題・データ破壊・テスト失敗
   - major: 設計の重大欠陥・パフォーマンス劣化・公開 API の不整合
   - minor: 命名・コメント・微細な readability・スタイル
4. 最終メッセージとして以下の JSON 1行のみを返す:
   {"critical": [{"file":"...", "line": N, "msg":"..."}], "major": [...], "minor": [...]}
"""
})
```

返答 JSON を parse して各 severity の件数を取得。

### 2-2. テレメトリ追記

```bash
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson pr "$pr_number" \
  --argjson iter "$iter" \
  --argjson c "$(echo "$findings" | jq '.critical | length')" \
  --argjson m "$(echo "$findings" | jq '.major | length')" \
  --argjson mn "$(echo "$findings" | jq '.minor | length')" \
  '{ts:$ts,source:"refine",pr_number:$pr,iter:$iter,critical:$c,major:$m,minor:$mn}' \
  >> .sweep/refine-metrics.jsonl
```

### 2-3. 閾値判定

```
if critical == 0 && major == 0 && minor <= max_minor:
  → success, フェーズ3 へ
if iter >= max_iter:
  → stuck, フェーズ3 へ（残指摘ありで終了）
otherwise:
  → 2-4 へ
```

### 2-4. 修正 agent

```
Agent({
  description: "Refine iteration <iter+1> fix",
  subagent_type: "claude",
  prompt: """
PR #<n>（branch: <branch>）の以下の指摘を修正してください:

CRITICAL:
<critical 指摘の file:line:msg を列挙>

MAJOR:
<major 指摘を列挙>

MINOR (excess minor が <minor - max_minor> 件あるので優先度高いものを <minor - max_minor> 件以上修正):
<minor 指摘を列挙>

手順:
1. `git checkout <branch>` で切り替え
2. develop エージェント (Agent(develop)) で順番に修正
3. テストが必要なら追加
4. `git push` で修正コミットを push
5. 最終メッセージ JSON: {"fixed_critical": N, "fixed_major": N, "fixed_minor": N, "commit": "<sha>"}
   または失敗時: {"failure": "<理由>"}
"""
})
```

失敗時はループ中断し stuck 扱いでフェーズ3 へ。

### 2-5. 次の反復
`iter+=1` してフェーズ2-1 に戻る。

## フェーズ3: レポート生成と終了

1. `total_dur=$(( $(date +%s) - start_ts ))` を計算
2. **最終 status を確定**:
   - 閾値到達 → `clean` (success)
   - max_iter 到達 → `iter_limit`
   - agent failure → `agent_failed`
3. **テレメトリ最終行を追記**（status 込み）
4. **Markdown レポート生成**:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
report=".sweep/report-refine-${ts}.md"
mkdir -p .sweep
cat > "$report" <<EOF
# refine report — $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Target
- PR: #${pr_number}
- Branch: ${branch}
- Iterations: ${iter}
- Final status: **${status}**
- Elapsed: ${total_dur}s

## Findings trend

| Iter | Critical | Major | Minor |
|---|---|---|---|
$(jq -r --argjson pr "$pr_number" 'select(.source == "refine" and .pr_number == $pr) | "| \(.iter) | \(.critical) | \(.major) | \(.minor) |"' .sweep/refine-metrics.jsonl)

## Remaining issues
$(if [[ "$status" != "clean" ]]; then echo "$findings" | jq -r '.critical[]?, .major[]?, .minor[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"'; else echo "なし（閾値到達）"; fi)
EOF

echo "Report written to $report"
```

5. **通知**: `sweep_notify "refine done" "PR #${pr_number}: ${status}, ${iter} iters" "<emoji>"` （issue-sweep と同じ `sweep_notify` 関数を流用、`.sweep/notify.url` が読まれる）
6. レポートパスをユーザーに最終表示

## 禁止行動

- **メインスレッド自身がコードを修正する**（CTO は実装に触らない、impl-wt や issue-sweep と同じ原則）
- review agent と fix agent を同じ呼び出しで混ぜる（独立性を保つ）
- 閾値到達してないのに「もういいでしょう」とループを打ち切る
- `max_iter` を超えても無限ループする
- minor の修正で副作用バグを入れない（修正後の review で critical が出たら反復継続）

## 失敗時の挙動

- review agent / fix agent のいずれかが failure → ループ中断、テレメトリ最終行に `status: "agent_failed"` を記録、レポート生成して終了
- worktree 作成失敗 → そもそも開始しない
- ネットワーク断・gh エラー → 60秒待って3回までリトライ、それでもダメならユーザー判断
