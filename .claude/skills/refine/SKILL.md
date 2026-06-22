---
name: refine
description: review→修正→再review を反復し critical/major=0 ∧ minor≤閾値 まで研磨後、auto-merge と Issue close まで実行する。
user-invocable: true
---

# refine

review → 修正 → 再 review を回し、PR をレビュー観点で「軽微指摘のみ」状態まで持っていくスキル。issue-sweep の各サブスキルが内部で持つ改善サイクルとは独立し、**既存ブランチ / PR に追加で適用**できる。

## 引数

- `/refine` — 現在のブランチ / PR を対象
- `/refine #<PR番号>` — 特定 PR を対象
- `/refine --max-minor <N>` — minor 指摘の上限（デフォルト 5）
- `/refine --max-iter <N>` — レビューループ反復上限（デフォルト 10）
- `/refine --no-merge` — 研磨のみで auto-merge しない（デフォルトはマージまで実行）

## 前提

- `git`, `gh` CLI 認証済み
- 対象 PR / ブランチが checkout 可能
- `.sweep/` ディレクトリへの書き込み権限（テレメトリ用）

## 状態管理 `.sweep/state.json`

sweep 系スキル共通の進行状態ファイル。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**review を再実行せず推定で `phase=terminal` にしてはならない**。terminal 化前に必ず最終 review を走らせ、その出力パスを `evidence` に append する。

**スキーマ:**
```json
{
  "skill": "refine",
  "started_at": "<ISO8601>",
  "updated_at": "<ISO8601>",
  "phase": "iterating" | "terminal",
  "iteration": <N>,
  "max_iter": <N>,
  "thresholds": {"critical": 0, "major": 0, "minor": <max_minor>},
  "last_counts": {"critical": <N>, "major": <N>, "minor": <N>},
  "evidence": ["<path>", ...],
  "termination_reason": null | "thresholds_met" | "max_iter" | "agent_failed" | "merge_failed" | "ci_gave_up" | "aborted",
  "pr_number": <N>
}
```

**更新タイミング:**
- フェーズ1 開始時に `phase=iterating, iteration=0, evidence=[]` で初期化
- 各反復終了時（2-2 テレメトリ追記直後）に `iteration += 1`, `last_counts` を最新の review 集計結果で上書き、`evidence` に当該反復のテレメトリ参照（`.sweep/refine-metrics.jsonl:<行番号>`）を append、`updated_at` 更新
- フェーズ3 で `phase=terminal` と `termination_reason` をセット。**直前に最終 review を走らせ evidence を追加してから terminal 化する**

`.sweep/` ディレクトリが無ければ `mkdir -p .sweep` で作成してから初期化する。

## フェーズ1: ターゲット特定とレビュー対象スキル決定

1. 引数が PR 番号: `gh pr view <n> --json number,headRefName,baseRefName,url`
2. 引数なし: 現ブランチで `gh pr view --json ...` を試す。なければ現ブランチを直接対象に
3. **worktree 確保（必須）**: メイン作業ツリーを保護するため、以下のいずれかで refine 用の worktree を確保する:
   - **既に worktree 内で起動された場合**（例: issue-sweep の engineer agent からの呼び出し）: `git rev-parse --show-toplevel` と `git worktree list --porcelain` を比較し、現在が worktree なら**再利用**（新規作成しない）
   - **メイン作業ツリーで起動された場合**（例: ユーザーが `/refine #42` を直接叩く）: `impl-wt` の `references/worktree-setup.md` に従い PR ブランチ用の worktree を新規作成。以後フェーズ2/3 の全操作は worktree 内で実行
4. `start_ts=$(date +%s)`, `iter=0`, `max_minor=5`, `max_iter=10` を初期化
4b. **`.sweep/state.json` を初期化** (`mkdir -p .sweep` 後):
   ```bash
   jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
         --argjson mi "$max_iter" --argjson mm "$max_minor" \
         --argjson pr "${pr_number:-null}" '{
     skill: "refine",
     started_at: $now, updated_at: $now,
     phase: "iterating", iteration: 0, max_iter: $mi,
     thresholds: {critical: 0, major: 0, minor: $mm},
     last_counts: {critical: null, major: null, minor: null},
     evidence: [],
     termination_reason: null,
     pr_number: $pr
   }' > .sweep/state.json
   ```
5. **HALT プロジェクト検知**（初回のみ、結果は変数に保持）:
   ```bash
   HAS_HALT=false
   if find . -name "*.templ" -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null | grep -q .; then
     HAS_HALT=true
   elif grep -rli "HALT\|HTMX+Atomic+Lit+Templ" docs/ SPEC.md README.md 2>/dev/null | grep -q .; then
     HAS_HALT=true
   fi
   ```
6. **レビュー対象スキル一覧**を決定:
   - 常に: `code-review`, `doc-drift`, `spec-audit`
   - `HAS_HALT=true` のみ: `halt-review` を追加

## フェーズ2: review → 修正ループ

各反復で `Agent(subagent_type=claude)` を**レビュースキルごとに並列起動**。**メインスレッドはコードに触れない**。

### 2-1. レビュー集約（並列）

決定したスキル群を**同一メッセージで並列に**起動する。各 agent は専門スキルを 1 つだけ実行し、JSON で指摘を返す。

```
Agent({
  description: "Refine iter <iter+1> — code-review",
  subagent_type: "claude",
  prompt: """
PR #<n>（branch: <branch>）に対して /code-review を Skill ツールで起動して実行。
得られた指摘を以下の severity で分類し、JSON 1行で最終メッセージとして返す:
- critical: バグ・セキュリティ問題・データ破壊・テスト失敗
- major: 設計の重大欠陥・パフォーマンス劣化・公開 API の不整合
- minor: 命名・コメント・微細な readability・スタイル

{"source": "code-review", "critical": [{"file":"...", "line": N, "msg":"..."}], "major": [...], "minor": [...]}
"""
})

Agent({
  description: "Refine iter <iter+1> — doc-drift",
  ... 同様、/doc-drift を実行、 "source": "doc-drift" で返す
})

Agent({
  description: "Refine iter <iter+1> — spec-audit",
  ... 同様、/spec-audit を実行、 "source": "spec-audit" で返す
  # spec-audit は通常 Issue を作成するスキル。refine からの呼び出し時は --report-only や --dry-run 相当で「Issue 化せず指摘リストだけ返す」モードで呼ぶこと。spec-audit 側にそのモードがなければ「Issue は作らず指摘 JSON のみ返してください」とプロンプトで明示
})

# HAS_HALT=true のときのみ追加
Agent({
  description: "Refine iter <iter+1> — halt-review",
  ... 同様、/halt-review を実行、 "source": "halt-review" で返す
})
```

各 agent の返答 JSON を集約:

```bash
# 全 source の critical / major / minor を結合
findings=$(printf '%s\n' "$resp_code" "$resp_doc" "$resp_spec" "$resp_halt" | \
  jq -s '{
    critical: map(.critical // []) | flatten,
    major:    map(.major // [])    | flatten,
    minor:    map(.minor // [])    | flatten,
    by_source: map({(.source): {c:(.critical|length), m:(.major|length), mn:(.minor|length)}}) | add
  }')
```

返答 JSON を parse して各 severity の合計件数を取得。

### 2-2. テレメトリ追記 + state.json 更新

```bash
# テレメトリ append
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson pr "$pr_number" \
  --argjson iter "$iter" \
  --argjson c "$(echo "$findings" | jq '.critical | length')" \
  --argjson m "$(echo "$findings" | jq '.major | length')" \
  --argjson mn "$(echo "$findings" | jq '.minor | length')" \
  --argjson by_src "$(echo "$findings" | jq '.by_source')" \
  --argjson halt "$HAS_HALT" \
  '{ts:$ts,source:"refine",pr_number:$pr,iter:$iter,critical:$c,major:$m,minor:$mn,by_source:$by_src,halt:$halt}' \
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

## フェーズ3: マージ → レポート生成と終了

1. `total_dur=$(( $(date +%s) - start_ts ))` を計算
2. **最終 status を確定**:
   - 閾値到達 → `clean`（マージへ進む）
   - max_iter 到達 → `iter_limit`（マージしない）
   - agent failure → `agent_failed`（マージしない）

3. **auto-merge → ポーリング → Issue close**（status=clean かつ `--no-merge` 未指定の場合のみ）:

```bash
gh pr merge <PR> --auto --merge --delete-branch
sweep_notify "refine: auto-merge queued" "PR #${pr_number}" ":hourglass:"

# issue-sweep と同じポーリング（statusCheckRollup 監視）
respawn=0
while true; do
  payload=$(gh pr view <PR> --json state,mergedAt,statusCheckRollup)
  state=$(echo "$payload" | jq -r .state)
  merged=$(echo "$payload" | jq -r '.mergedAt // "null"')
  failed=$(echo "$payload" | jq -r '[.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name] | join(",")')
  pending=$(echo "$payload" | jq '[.statusCheckRollup[]? | select(.conclusion == null and .status != "COMPLETED")] | length')

  [[ "$state" == "MERGED" ]] && break

  if [[ "$state" == "CLOSED" && "$merged" == "null" ]]; then
    status="merge_failed"; break
  fi

  if [[ -n "$failed" && "$pending" -eq 0 ]]; then
    if (( respawn >= 2 )); then status="ci_gave_up"; merge_failure="$failed"; break; fi
    respawn=$((respawn+1))
    gh pr comment <PR> --body "refine: マージ前 CI 失敗を検知（attempt ${respawn}/3、checks: $failed）。修正 agent を再起動します。"
    # 2-3 と同じ CI fix プロンプトで Agent(claude) 起動
    continue
  fi
  sleep 60
done

# マージ成功時、リンクされた Issue を close
if [[ "$state" == "MERGED" ]]; then
  closing_issues=$(gh pr view <PR> --json closingIssuesReferences -q '.closingIssuesReferences[].number')
  for issue in $closing_issues; do
    gh issue close "$issue" --comment "Closed by PR #${pr_number} (refined and auto-merged via /refine, iters=${iter})"
  done
fi
```

`--no-merge` 指定時はこのステップを完全スキップして直接 4 へ。

4. **テレメトリ最終行を追記**（status 込み）

4b. **最終 review を再実行して state.json の last_counts / evidence を確定**:
   - status=`clean` を主張する場合は **必ずもう一度 2-1 のレビューを走らせ**、最新カウントが閾値を満たしていることを再確認する（推定で clean にしない）
   - 結果を `.sweep/refine-metrics.jsonl` に append し、state.json の `last_counts` / `evidence` / `updated_at` を更新

4c. **state.json を terminal 化**:
```bash
reason="thresholds_met"   # または iter_limit / agent_failed / merge_failed / ci_gave_up / aborted
jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
   .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
```

5. **Markdown レポート生成**（`## Evidence` セクション必須、state.json の `evidence` を引用）:

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

## Evidence

$(jq -r '.evidence[] | "- \(.)"' .sweep/state.json)

## Remaining issues
$(if [[ "$status" != "clean" ]]; then echo "$findings" | jq -r '.critical[]?, .major[]?, .minor[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"'; else echo "なし（閾値到達）"; fi)
EOF

echo "Report written to $report"
```

5. **通知**: `sweep_notify "refine done" "PR #${pr_number}: ${status}, ${iter} iters" "<emoji>"` （issue-sweep と同じ `sweep_notify` 関数を流用、`.sweep/notify.url` が読まれる）
6. **呼び出し元への返答**: 最終メッセージとして以下の JSON 1行を出力（issue-sweep の engineer agent などが parse できるよう、Markdown レポートのパス案内に**先行して** JSON 行を出すこと）:

```json
{"status":"<clean|iter_limit|agent_failed|merge_failed>","pr_number":<N>,"iter":<K>,"critical_remaining":<N>,"major_remaining":<N>,"minor_remaining":<N>,"merged":<true|false>,"report_path":".sweep/report-refine-<ts>.md"}
```

- `--no-merge` 指定時は `merged: false` で固定（auto-merge をしていないため）
- `iter_limit` でも `critical_remaining=0 ∧ major_remaining=0` のときは呼び出し元が「軽微残りで OK」と判定できる
- レポートパスはユーザー向けの最終表示と JSON 両方に含める

## 禁止行動

- **メインスレッド自身がコードを修正する**（CTO は実装に触らない、impl-wt や issue-sweep と同じ原則）
- review agent と fix agent を同じ呼び出しで混ぜる（独立性を保つ）
- 閾値到達してないのに「もういいでしょう」とループを打ち切る
- `max_iter` を超えても無限ループする
- minor の修正で副作用バグを入れない（修正後の review で critical が出たら反復継続）
- **必須レビュー（code-review / doc-drift / spec-audit）の一部をスキップする**（全 4 観点を統合して判定するため）
- **HALT プロジェクトで halt-review をスキップする**（フェーズ1 で HAS_HALT=true なら必ず並列起動）
- **`.sweep/state.json` を `phase=terminal` にする前に最終 review を再実行せず、推定で `clean` を宣言する**（iter 途中の counts を信じて terminal 化するのは禁止。フェーズ3 ステップ4b で必ず最終 review を走らせる）
- **`.sweep/state.json` の `evidence` 配列が空のままフェーズ3 に進む / terminal 化する**
- レポートに `## Evidence` セクションを書かない（state.json の evidence をそのまま引用する形で必ず残す）
- **status=clean なのに auto-merge をスキップする**（`--no-merge` 明示時を除く。研磨だけでマージしないとループの意味がない）
- マージ完了確認をスキップしてレポート生成に進む
- **メイン作業ツリーで checkout して PR ブランチに切り替える**（worktree 隔離を破ってメインを汚す原因。フェーズ1-3 で必ず worktree を確保すること）

## 失敗時の挙動

- review agent / fix agent のいずれかが failure → ループ中断、テレメトリ最終行に `status: "agent_failed"` を記録、レポート生成して終了
- worktree 作成失敗 → そもそも開始しない
- ネットワーク断・gh エラー → 60秒待って3回までリトライ、それでもダメならユーザー判断
