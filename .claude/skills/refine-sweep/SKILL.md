---
name: refine-sweep
description: 全コードベースを 4 観点で連続レビューし、critical/major の指摘を反復 PR で修正→マージしてゼロまで持っていく。
user-invocable: true
---

# refine-sweep

`/refine` の全コードベース版。特定 PR ではなくリポジトリ全体を対象に `/code-review` / `/doc-drift` / `/spec-audit`（HALT 検知時は `/halt-review`）を並列実行し、critical + major の指摘を 1 PR にまとめて修正・マージするサイクルを回す。

`/refine` は1つの PR を磨くスキル。`/refine-sweep` は **コードベース全体を継続的にゼロ近くへ持っていくスキル**。issue-sweep と同じ CTO + agent 構造、`.sweep/` 配下に状態を残す。

## 引数

- `/refine-sweep` — 全コードベース対象、critical + major を fix
- `/refine-sweep --max-iter N` — 反復上限（デフォルト 5）
- `/refine-sweep --include-minor` — minor も fix 対象に加える（デフォルトは critical + major のみ）
- `/refine-sweep --max-minor N` — `--include-minor` 時の minor 残許容数（デフォルト 20）
- `/refine-sweep --abort` — 実行中の sweep を中止し lock を削除

## 前提

- `git`, `gh` CLI 認証済み
- 現在のブランチが base（develop / main 等）。`git branch --show-current` で取得
- リポジトリで auto-merge 有効化済み
- `.sweep/` 書き込み権限

## フェーズ0: lock 取得（issue-sweep と同じ heartbeat 方式）

1. `.sweep/lock` が存在し timestamp が 2 時間以内 → 「他 sweep 実行中」と表示し終了
2. それ以外は `echo "$PPID:$(date +%s)" > .sweep/lock`
3. フェーズ3 / 中断 / `--abort` 時に `rm -f .sweep/lock`

## フェーズ1: 環境準備

1. `base_branch=$(git branch --show-current)` を記録
2. HALT 検知（refine と同じロジック）:
   - `*.templ` ファイル存在 or 仕様書に「HALT / HTMX+Atomic+Lit+Templ」記述 → `HAS_HALT=true`
3. レビュー対象スキル一覧:
   - 常に: `/code-review`, `/doc-drift`, `/spec-audit`
   - HAS_HALT=true: `/halt-review` も追加
4. 反復用 worktree を `refine-sweep/<timestamp>` ブランチで作成（meta 作業用、各反復ではここに修正コミットして PR を作る）
5. `start_ts=$(date +%s)`, `iter=0`, `max_iter=5`, `include_minor=false`, `max_minor=20` を初期化

## フェーズ2: review → fix → merge ループ

### 2-1. 反復冒頭

```bash
echo "$PPID:$(date +%s)" > .sweep/lock          # heartbeat
git fetch origin "$base_branch" 2>/dev/null || true
git pull --ff-only origin "$base_branch" 2>/dev/null || true
```

### 2-2. レビュー集約（4 観点並列）

`/refine` の 2-1 と同じ形式で `Agent(claude)` を並列起動。ただし**対象は PR ではなく base ブランチの HEAD**:

```
Agent({
  description: "refine-sweep iter <iter+1> — code-review",
  subagent_type: "claude",
  prompt: """
リポジトリ全体に対して /code-review を Skill ツールで起動して実行。
得られた指摘を以下の severity で分類し、JSON 1行で最終メッセージとして返す:
- critical: バグ・セキュリティ問題・データ破壊・テスト失敗
- major: 設計の重大欠陥・パフォーマンス劣化・公開 API の不整合
- minor: 命名・コメント・微細な readability・スタイル

{"source": "code-review", "critical": [...], "major": [...], "minor": [...]}
"""
})

# /doc-drift, /spec-audit, /halt-review も同様に並列起動
```

各 agent の返答を `/refine` と同じ jq で集約。

### 2-3. テレメトリ追記

```bash
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson iter "$iter" \
  --argjson c "$(echo "$findings" | jq '.critical | length')" \
  --argjson m "$(echo "$findings" | jq '.major | length')" \
  --argjson mn "$(echo "$findings" | jq '.minor | length')" \
  --argjson by_src "$(echo "$findings" | jq '.by_source')" \
  --argjson halt "$HAS_HALT" \
  '{ts:$ts,source:"refine-sweep",iter:$iter,critical:$c,major:$m,minor:$mn,by_source:$by_src,halt:$halt}' \
  >> .sweep/refine-metrics.jsonl
```

### 2-4. 閾値判定

```
target_count = critical + major
if include_minor: target_count += max(0, minor - max_minor)

if target_count == 0:
  → clean, フェーズ3 へ（成功）
if iter >= max_iter:
  → iter_limit, フェーズ3 へ（残指摘ありで終了）
otherwise:
  → 2-5 へ
```

### 2-5. fix engineer agent に丸投げ（メインは JSON だけ受け取る）

**CTO 原則**: メインスレッドはコード修正・コミット・PR 操作・CI 待ち、いずれにも直接タッチしない。すべて engineer agent に閉じ込めて context を線形に保つ。

```
Agent({
  description: "refine-sweep iter <iter+1> fix",
  subagent_type: "claude",
  prompt: """
レビューで検出された以下の指摘を修正し、PR 作成→auto-merge 予約→**マージ完了まで内部でハンドリング**してください。
メインスレッドには JSON 1 行だけを返します（develop / review / push ログをメインに流さない）。

CRITICAL: <件数・file:line:msg 列挙>
MAJOR: <列挙>
（--include-minor 時は MINOR の優先度高い <minor - max_minor> 件以上も含める）

手順:
1. **base_branch を最新化**: `git fetch origin <base_branch> && git checkout <base_branch> && git pull --ff-only origin <base_branch>`（直前反復のマージ分を取り込んでから分岐する）
2. 反復用ブランチ `refine-sweep/<timestamp>-iter-<iter+1>` を最新の base_branch から作成
3. develop エージェント (`Agent(develop)`) で順に修正＋テスト
4. `git push -u origin <branch>`
5. `gh pr create --base <base_branch> --title "refine-sweep iter <iter+1>: critical/major fixes" --body <findings 一覧>`
6. `gh pr merge <PR> --auto --merge --delete-branch` で auto-merge 予約
7. **マージ完了をポーリング**: issue-sweep フェーズ2-4 と同じ statusCheckRollup 監視。`MERGED` まで待機。CI 失敗が確定したら同じ agent コンテキスト内で develop agent を再起動して修正 push（最大 3 回まで）。3 回連続失敗なら `ci_gave_up` で返す
8. マージ完了したら最終 JSON を返す

返答 JSON 1行:
{"pr_number": <N>, "pr_url": "<URL>", "branch": "<branch>", "fixed_critical": <N>, "fixed_major": <N>, "fixed_minor": <N>, "merged": true, "ci_respawns": <K>}

CI 諦め時:
{"pr_number": <N>, "pr_url": "<URL>", "failure": "ci_gave_up", "failed_checks": "<checks>", "ci_respawns": 3}

その他失敗時:
{"failure": "<1行で原因>", "phase": "<どのステップで失敗したか>"}

返答ルール:
- 上記 JSON 以外を最終メッセージに含めない
- 内部 log（Plan / Develop / Review / Push の詳細）はメインに残さない（agent context 内で消える）
- 「ユーザー確認」「次へ進めますか」等で停止しない
"""
})
```

メインスレッドは返答 JSON を parse:
- `merged: true` → 次反復 (`iter += 1`) で 2-1 へ
- `failure: "ci_gave_up"` または他 failure → フェーズ3 へ status=`agent_failed` で抜ける
- 反復間で findings が減らないケース（同一 findings が 2 反復続いた）→ `fix_ineffective` で終了

**マージされた修正は次の review で消えるはず**なので、review→fix→merge の往復で findings を削っていく。

## フェーズ3: 完了処理とレポート

1. status を確定（`clean` / `iter_limit` / `agent_failed`）
2. `git worktree prune` で残存 worktree 整理
3. レポート生成 `.sweep/report-refine-sweep-<ts>.md`:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
report=".sweep/report-refine-sweep-${ts}.md"
mkdir -p .sweep
{
  echo "# refine-sweep report — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Summary"
  echo "- Base branch: ${base_branch}"
  echo "- Iterations: ${iter}"
  echo "- Final status: **${status}**"
  echo "- Elapsed: $(( $(date +%s) - start_ts ))s"
  echo
  echo "## Findings trend"
  echo
  echo "| Iter | Critical | Major | Minor |"
  echo "|---|---|---|---|"
  jq -r 'select(.source == "refine-sweep") | "| \(.iter) | \(.critical) | \(.major) | \(.minor) |"' .sweep/refine-metrics.jsonl
  echo
  echo "## Remaining findings"
  if [[ "$status" != "clean" ]]; then
    echo "$findings" | jq -r '.critical[]?, .major[]?, .minor[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"'
  else
    echo "なし（critical/major 0 達成）"
  fi
} > "$report"
```

4. `rm -f .sweep/lock` でロック解除
5. `sweep_notify "refine-sweep done" "${iter} iters, status=${status}, report: ${report}" ":checkered_flag:"`
6. ユーザーにレポートパスを返す

## 禁止行動

- **メインスレッド自身がコードを修正する / コミットする / PR を編集する**（CTO は実装に触らない）
- **メインスレッドで PR マージ完了のポーリングや CI fix ループを直接回す**（コンテキスト線形保持のため fix engineer agent 内に閉じ込める。issue-sweep のフェーズ2-4 のようにメインで sleep するのではなく、refine-sweep では engineer agent が内部で待つ）
- **fix agent の Plan/Develop/Review/Push log をメイン context に取り込もうとする**（JSON 1行のみ受け取る）
- review agent と fix agent を同じ呼び出しで混ぜる
- critical/major が残っているのにループを打ち切る
- max_iter を超えても無限ループする
- `--include-minor` なしで minor を修正する（暴走防止）
- fix agent が `--no-merge` で済ませる（必ず auto-merge 予約まで実行）
- ユーザーに「続けますか」と聞く（Stop Hook が押し戻す）

## 失敗時の挙動

- review agent failure: テレメトリに `agent_failed` を記録しレポート生成して終了
- fix agent failure: 反復ブランチを削除（`git push origin --delete <branch>`、可能なら）してテレメトリ記録・レポート生成・終了
- CI 失敗が 3 回連続: ユーザー判断を仰ぐ（refine と同じ）
- 同じ findings が連続 2 反復で減らない: 「fix が効いていない」と判定して終了
