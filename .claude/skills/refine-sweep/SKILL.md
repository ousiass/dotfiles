---
name: refine-sweep
description: 全コードベースを 4 観点で連続レビューし、ドメイン別並列 PR で critical/major=0 ∧ minor≤5 まで磨く。spinoff Issue も自動 /issue-sweep に委譲して実装まで完了。
user-invocable: true
---

# refine-sweep

`/refine` の全コードベース版。特定 PR ではなくリポジトリ全体を対象に `/code-review` / `/doc-drift` / `/spec-audit`（HALT 検知時は `/halt-review`）を並列実行し、critical + major の指摘を 1 PR にまとめて修正・マージするサイクルを回す。

`/refine` は1つの PR を磨くスキル。`/refine-sweep` は **コードベース全体を継続的にゼロ近くへ持っていくスキル**。issue-sweep と同じ CTO + agent 構造、`.sweep/` 配下に状態を残す。

## 引数

- `/refine-sweep` — 全コードベース対象、**critical + major + minor すべて**を fix（デフォルト挙動）
- `/refine-sweep --max-iter N` — 反復上限（デフォルト 5）
- `/refine-sweep --no-minor` — minor を fix 対象から外し critical + major のみ修正（軽量モード）
- `/refine-sweep --max-minor N` — minor 残許容数（デフォルト 5、`/refine` と揃えた値。0 を指定すれば完全に磨ききる）
- `/refine-sweep --no-follow-spinoffs` — spinoff Issue を自動 sweep するのを抑止
- `/refine-sweep --max-rounds N` — spinoff 追跡の上限周回数（**デフォルト 10、最大 20**）。通常はこの値に到達する前に spinoff が枯れて自然終了する
- `/refine-sweep --abort` — 実行中の sweep を中止し lock を削除

## 前提

- `git`, `gh` CLI 認証済み
- 現在のブランチが base（develop / main 等）。`git branch --show-current` で取得
- `.sweep/` 書き込み権限

## 状態管理 `.sweep/state.json`

sweep 系スキル共通の進行状態ファイル。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**review を再実行せず推定で `phase=terminal` にしてはならない**。terminal 化前に必ず最新 review を走らせ、その出力パスを `evidence` に append する。

**スキーマ:**
```json
{
  "skill": "refine-sweep",
  "started_at": "<ISO8601>",
  "updated_at": "<ISO8601>",
  "phase": "iterating" | "terminal",
  "iteration": <N>,
  "max_iter": <N>,
  "thresholds": {"critical": 0, "major": 0, "minor": <max_minor>},
  "last_counts": {"critical": <N>, "major": <N>, "minor": <N>},
  "evidence": ["<path>", ...],
  "termination_reason": null | "thresholds_met" | "max_iter" | "agent_failed" | "fix_ineffective" | "aborted"
}
```

**更新タイミング:**
- フェーズ0/1 開始時に `phase=iterating, iteration=0, evidence=[]` で初期化
- 各反復終了時（2-3 テレメトリ追記直後）に `iteration += 1`, `last_counts` を最新の review 集計結果で上書き、`evidence` に当該反復のテレメトリ行（例: `.sweep/refine-metrics.jsonl:42` のように行番号付きで）または個別 review レポートのパスを append、`updated_at` 更新
- フェーズ3 で `phase=terminal` と `termination_reason` をセット。**直前に最終 review を走らせ evidence を追加してから terminal 化する**

**更新ヘルパー（heredoc + jq で in-place 書き換え）:**

```bash
write_sweep_state() {
  local patch="$1"  # JSON patch (top-level merge)
  local file=".sweep/state.json"
  local now=$(date -u +%Y-%m-%dT%H:%M:%SZ)
  local tmp="${file}.tmp"
  jq --arg now "$now" --argjson patch "$patch" '. + $patch | .updated_at = $now' "$file" > "$tmp" && mv "$tmp" "$file"
}
```

## フェーズ0: lock 取得（issue-sweep と同じ heartbeat 方式）

1. `.sweep/lock` が存在し timestamp が 2 時間以内 → 「他 sweep 実行中」と表示し終了
2. それ以外は `echo "$PPID:$(date +%s)" > .sweep/lock`
3. **`.sweep/state.json` を初期化**:
   ```bash
   jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson mi "$max_iter" --argjson mm "$max_minor" '{
     skill: "refine-sweep",
     started_at: $now, updated_at: $now,
     phase: "iterating", iteration: 0, max_iter: $mi,
     thresholds: {critical: 0, major: 0, minor: $mm},
     last_counts: {critical: null, major: null, minor: null},
     evidence: [],
     termination_reason: null
   }' > .sweep/state.json
   ```
4. フェーズ3 / 中断 / `--abort` 時に `rm -f .sweep/lock`。**`.sweep/state.json` は残す**（履歴・監査用）が、必ず `phase=terminal` にしてから抜けること

## フェーズ1: 環境準備とドメイン一覧抽出

1. `base_branch=$(git branch --show-current)` を記録
2. HALT 検知（refine と同じロジック）:
   - `*.templ` ファイル存在 or 仕様書に「HALT / HTMX+Atomic+Lit+Templ」記述 → `HAS_HALT=true`
3. レビュー対象スキル一覧:
   - 常に: `/code-review`, `/doc-drift`, `/spec-audit`
   - HAS_HALT=true: `/halt-review` も追加
4. **ドメイン一覧を仕様書から抽出**（ステージ分けの軸として使用）:
   - 仕様書の場所を CLAUDE.md または Glob (`docs/spec/**/*.md`, `specs/**/*.md`, `SPEC.md`) で特定
   - 仕様書本文から「Frontend / Backend / DB / Database / CI / CD / Infra / Shared / Common / Mobile / Admin」等の H2 セクションや「## ドメイン」配下の項目を抽出
   - 該当見出しが無ければ標準セットにフォールバック: `["db", "backend", "frontend", "ci"]`
   - 抽出結果を `DOMAINS=(db backend frontend ci ...)` として保持。**順序は依存順**（db → backend → frontend → ci）を仕様書記述順から推定。明示的依存記述があれば優先
   - **`other` ドメインを末尾に必ず追加**（どのドメインにも振り分けられない指摘の受け皿）
5. 各ドメインの**ファイルパスマッピング**も仕様書から取得（記述があれば）:
   - 例: `frontend: apps/web/**, src/components/**` のような記述があれば使う
   - 無ければ標準推測: `frontend: apps/web/* | web/* | src/components/* | *.tsx | *.jsx | *.vue`、`backend: apps/api/* | api/* | src/server/* | *.go`、`db: migrations/* | schema.sql | db/* | prisma/*`、`ci: .github/workflows/* | ci/* | Dockerfile`
6. `start_ts=$(date +%s)`, `iter=0`, `max_iter=5`, `include_minor=true`, `max_minor=5`, `round=0`, `max_rounds=10`, `follow_spinoffs=true` を初期化（`--no-minor` 指定時のみ `include_minor=false`、`--no-follow-spinoffs` 指定時のみ `follow_spinoffs=false`）
7. ユーザーに「検出ドメイン: db, backend, frontend, ci, other」と並びをそのまま表示（確認は取らない）

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

### 2-3. テレメトリ追記 + state.json 更新

```bash
# テレメトリ append（既存）
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

**evidence の append 規則**: 各反復で必ず最低 1 件追加する。空の状態でフェーズ3 に進ませない。

### 2-4. ドメイン振り分けと閾値判定

**指摘を `DOMAINS` 配列の各要素に振り分ける**（findings の各 file path をマッピングと照合し、最初にマッチしたドメインへ。どこにもマッチしなければ `other`）:

```bash
echo "$findings" | jq -c '
  def classify(f):
    if   (f|test("apps/web|web/|src/components|\\.tsx$|\\.jsx$|\\.vue$")) then "frontend"
    elif (f|test("apps/api|^api/|src/server|\\.go$")) then "backend"
    elif (f|test("migrations/|schema\\.sql|^db/|prisma/")) then "db"
    elif (f|test("\\.github/workflows|^ci/|Dockerfile")) then "ci"
    else "other" end;
  {
    domains: (
      [.critical[], .major[], .minor[]]
      | group_by(classify(.file // ""))
      | map({ key: classify(.[0].file // ""), value: . })
      | from_entries
    )
  }'
```

（実際にはフェーズ1 で取得したマッピング規則と DOMAINS 順を反映する。上記は標準セットの例）

**閾値判定:**

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

### 2-5. ドメイン別並列 fix engineer agent（メインは JSON だけ受け取る）

**CTO 原則**: メインスレッドはコード修正・コミット・PR 操作・CI 待ち、いずれにも直接タッチしない。各ドメインの fix を **engineer agent ごとに 1 つ立て、同一メッセージで並列起動**する（issue-sweep の `--parallel` と同じ発想）。

**並列ポリシー:**
- `DOMAINS` 配列の順序が **依存順**（db → backend → frontend → ci）
- 依存があるドメイン群は**順に sequential**、独立同士は並列起動可
- 標準セット `[db, backend, frontend, ci, other]` の場合:
  - 第 1 ウェーブ: `db` のみ単独実行（スキーマ変更は他に波及するため）
  - 第 1 ウェーブのマージ完了後、第 2 ウェーブ: `backend, frontend, ci, other` を並列起動
- 仕様書から別の依存順が読み取れた場合はそれに従う
- **指摘が 0 件のドメインは agent 起動せずスキップ**

各 ウェーブ内の各ドメイン agent プロンプト:

```
Agent({
  description: "refine-sweep iter <iter+1> fix [<DOMAIN>]",
  subagent_type: "claude",
  prompt: """
ドメイン `<DOMAIN>` に分類された以下の指摘を修正し、PR 作成 → CI 緑待ち → 直接マージ → MERGED まで内部でハンドリングしてください。

CRITICAL: <このドメインの critical 一覧>
MAJOR: <このドメインの major 一覧>
（--include-minor 時は MINOR も）

このドメインのファイル範囲: <フェーズ1 で取得したマッピング、例: apps/web/**, src/components/**>
**範囲外のファイルは絶対に変更しない**（他ドメイン agent と競合するため）。範囲外の修正が必要と判断したら failure で返す。

手順:
1. base_branch を最新化: `git fetch origin <base_branch> && git checkout <base_branch> && git pull --ff-only origin <base_branch>`
2. 反復用ブランチ `refine-sweep/<timestamp>-iter-<iter+1>-<DOMAIN>` を最新の base_branch から作成
3. `Agent(develop)` で順に修正＋テスト（範囲外のファイルを触らない厳守）
4. `git push -u origin <branch>`
5. `gh pr create --base <base_branch> --title "refine-sweep iter <iter+1> [<DOMAIN>]: critical/major fixes" --body <findings 一覧>`
6. statusCheckRollup ポーリングで全 check 完了 ∧ FAILURE なしを確認してから `gh pr merge <PR> --merge --delete-branch` を直接実行（`--auto` は使わない）
7. MERGED まで確認。CI 失敗時は内部で fix 再起動（最大 3 回）

返答 JSON:
{"domain": "<DOMAIN>", "pr_number": <N>, "pr_url": "<URL>", "branch": "<branch>", "fixed_critical": <N>, "fixed_major": <N>, "fixed_minor": <N>, "merged": true, "ci_respawns": <K>}

該当指摘 0 件で skip した場合: {"domain": "<DOMAIN>", "skipped": true}
CI 諦め: {"domain": "<DOMAIN>", "pr_number": <N>, "failure": "ci_gave_up", "failed_checks": "<checks>"}
範囲外修正が必要: {"domain": "<DOMAIN>", "failure": "scope_violation", "needed_files": [...]}
マージ失敗: {"domain": "<DOMAIN>", "pr_number": <N>, "failure": "merge_failed", "error": "<gh stderr>"}
その他: {"domain": "<DOMAIN>", "failure": "<理由>"}

返答ルール:
- JSON 1 行以外を最終メッセージに含めない
- 内部 log はメインに残さない
- ユーザー確認で停止しない
"""
})
```

**メインスレッドの集約:**
- ウェーブ内の全 agent の JSON を集める
- 1 つでも `failure` があれば次反復に進まず、フェーズ3 へ status=`agent_failed` で抜ける
- ただし `scope_violation` は次反復で別ドメインに振り直されるので fatal にしない（その分だけキューに残す）
- `merge_failed` も agent_failed として扱う（branch protection や権限の問題が疑われるためユーザー判断が要る）
- 全 merged ならウェーブ完了 → 次ウェーブへ
- 全ウェーブ完了 → `iter += 1` で 2-1 へ
- 反復間で **同一の findings 集合**（`file:line:msg` の fingerprint set）が連続 2 反復で完全一致 → `fix_ineffective` で終了。**件数だけ見て判定しない**（fix が新規 finding を生んでいる場合は前 iter とは集合が異なるので継続する）

**マージされた修正は次の review で消えるはず**なので、review→domain fix→merge の往復で findings を削っていく。

**fix_ineffective 判定の fingerprint 比較:**

各反復の review 集計直後に以下を実行して findings の fingerprint set を保存・比較する。前 iter と完全一致した時だけ打ち切る:

```bash
# 現 iter の fingerprint set を保存
echo "$findings" | jq -c '
  [.critical[], .major[], .minor[]
   | "\(.file // "?"):\(.line // 0):\(.msg // "")"]
  | sort | unique
' > ".sweep/findings-iter-${iter}.json"

# 前 iter と完全一致 → fix_ineffective
prev_file=".sweep/findings-iter-$((iter-1)).json"
if [[ "$iter" -ge 1 && -f "$prev_file" ]]; then
  curr=$(cat ".sweep/findings-iter-${iter}.json")
  prev=$(cat "$prev_file")
  if [[ "$curr" == "$prev" && "$curr" != "[]" ]]; then
    status="fix_ineffective"
    break
  fi
fi
```

これにより:
- iter N で 5 件 → iter N+1 で同じ 5 件残っている: 打ち切り（本当に効いてない）
- iter N で 5 件 → iter N+1 で 2 件直して 3 件新規発見（計 6 件）: **継続**（新規 finding が出てきても fix 中とみなす）
- iter N で 5 件 → iter N+1 で 5 件中 3 件直して 3 件新規（計 5 件、件数同じ）: **継続**（fingerprint set が違うため）

## フェーズ3: 完了処理とレポート

### 3-0. spinoff Issue 検出と自動実装

refine-sweep 中に develop agent が `/spinoff-issue` で作成した Issue を検出し、**自動で `/issue-sweep` に委譲して全部実装する**（デフォルト挙動）:

```bash
sweep_start_iso="<フェーズ1 で記録した開始時刻>"
new_issues=$(gh issue list --state open --search "created:>=${sweep_start_iso}" --json number,title,labels,body --limit 200)
# /spinoff-issue が付与する `spinoff` ラベルを目印に検出
spinoffs=$(echo "$new_issues" | jq -r '[.[] | select(
  ([.labels[]?.name] | index("spinoff")) != null
)] | map(.number) | join(" ")')
```

判定:
- spinoffs が**空** → 3-1 へ
- spinoffs があり、`--no-follow-spinoffs` 指定なし、`round < max_rounds`:
  - `round += 1` をインクリメント
  - 通知 `sweep_notify "refine-sweep: spinoffs detected" "${#spinoffs} 件を /issue-sweep に委譲" ":arrows_counterclockwise:"`
  - **`Agent(claude)` で `/issue-sweep <spinoff番号 列挙>` を起動**してすべて実装させる:
    ```
    Agent({
      description: "refine-sweep round <round>: spinoff issue-sweep",
      subagent_type: "claude",
      prompt: """
      /issue-sweep <spinoffs> を Skill ツールで起動し、すべての spinoff Issue を実装・マージ完了させてください。
      issue-sweep の標準フロー（impl-wt → refine → CI 緑待ち → 直接マージ → close）に従う。
      完了したら以下の JSON 1 行を返す:
      {"merged": <N>, "failed": <N>, "report_path": "<path>"}
      """
    })
    ```
  - issue-sweep が完了したら、それ自身が新たな spinoff を発生させている可能性があるので **3-0 に戻ってループ**（同じ round カウンタを共有して暴走を防ぐ）
  - `round >= max_rounds` 到達時 or `follow_spinoffs=false`: レポートに残 spinoff を列挙 + warning 通知して終了

これにより refine-sweep → 改善 PR → spinoff 検出 → issue-sweep → 実装完了 → 再度 refine-sweep からチェーンする運用が無人化される。

### 3-1. 完了処理

1. status を確定（`clean` / `iter_limit` / `agent_failed` / `fix_ineffective`）
2. **最終 review 実行（terminal 化前の必須ステップ）**:
   - 直近の 2-2 から base が動いている可能性があるため、フェーズ2-2 と同じ並列 review を **もう一度** 走らせて最終 `last_counts` を取得する
   - 結果を 2-3 と同じ手順で `.sweep/refine-metrics.jsonl` に append し、state.json の `last_counts` と `evidence` を更新する（**最低 1 件 evidence が増えていること**）
   - status の判定はこの最終 review の counts を基準にする（推定で `clean` にしない）
3. `git worktree prune` で残存 worktree 整理
4. **state.json を terminal 化**:
   ```bash
   reason="thresholds_met"   # または iter_limit / agent_failed / fix_ineffective / aborted
   jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
     .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
   ```
5. レポート生成 `.sweep/report-refine-sweep-<ts>.md`（**`## Evidence` セクション必須**、state.json の `evidence` を引用）:

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
  echo "- Final status: **${status}** (reason: ${reason})"
  echo "- Elapsed: $(( $(date +%s) - start_ts ))s"
  echo
  echo "## Findings trend"
  echo
  echo "| Iter | Critical | Major | Minor |"
  echo "|---|---|---|---|"
  jq -r 'select(.source == "refine-sweep") | "| \(.iter) | \(.critical) | \(.major) | \(.minor) |"' .sweep/refine-metrics.jsonl
  echo
  echo "## Evidence"
  echo
  echo "（各反復で参照したテレメトリ行 / レポートパス。state.json の evidence をそのまま列挙）"
  jq -r '.evidence[] | "- \(.)"' .sweep/state.json
  echo
  echo "## Remaining findings"
  if [[ "$status" != "clean" ]]; then
    echo "$findings" | jq -r '.critical[]?, .major[]?, .minor[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"'
  else
    echo "なし（critical/major 0 達成）"
  fi
} > "$report"
```

6. `rm -f .sweep/lock` でロック解除（state.json は terminal のまま残す）
7. `sweep_notify "refine-sweep done" "${iter} iters, status=${status}, report: ${report}" ":checkered_flag:"`
8. ユーザーにレポートパスを返す

## 禁止行動

- **メインスレッド自身がコードを修正する / コミットする / PR を編集する**（CTO は実装に触らない）
- **メインスレッドで PR マージ完了のポーリングや CI fix ループを直接回す**（コンテキスト線形保持のため fix engineer agent 内に閉じ込める。issue-sweep のフェーズ2-4 のようにメインで sleep するのではなく、refine-sweep では engineer agent が内部で待つ）
- **fix agent の Plan/Develop/Review/Push log をメイン context に取り込もうとする**（JSON 1行のみ受け取る）
- review agent と fix agent を同じ呼び出しで混ぜる
- **ドメイン分けせず 1 PR に全 critical+major 修正を詰める**（差分肥大化・レビュー困難・競合多発の元）
- **fix agent がドメインのファイル範囲を超えて他ドメインの src を編集する**（scope_violation で返すべき）
- critical/major が残っているのにループを打ち切る
- max_iter を超えても無限ループする
- **デフォルトで minor をスキップする**（`--no-minor` 明示時のみ minor 修正を省略可能。それ以外は minor も fix 対象だが、許容数は `max_minor=5` まで残してよい）
- **`.sweep/state.json` を `phase=terminal` にする前に最終 review を再実行せず、推定で `clean` を宣言する**（iter 2 以降のレビューをスキップして「spinoff したから clean だろう」と判定するのは禁止。3-1 ステップ2 で必ず最終 review を走らせる）
- **`.sweep/state.json` の `evidence` 配列が空のままフェーズ3 に進む / terminal 化する**（各反復で最低 1 件追加するルールを破らない）
- レポートに `## Evidence` セクションを書かない（state.json の evidence をそのまま引用する形で必ず残す）
- **spinoff の自動 issue-sweep 委譲をスキップする**（`--no-follow-spinoffs` 明示時のみ。それ以外は spinoff も最大 10 周まで自動で全実装させる、spinoff 0 で自然終了）
- **「spinoff も追跡しますか？」「次の round に進みますか？」のような確認をユーザーに取る**（デフォルトで全 round 自動継続。`--no-follow-spinoffs` 明示指定時以外、ユーザーに二択を投げない）
- fix agent が `--no-merge` で済ませる（CI 緑後に `gh pr merge --merge --delete-branch` を必ず実行）
- **fix agent が `gh pr merge --auto` を使う**（リポジトリ設定 `allow_auto_merge` に挙動が依存し、OFF だと GraphQL エラーで止まる。CI 緑をポーリングしてから直接マージする方式に統一）
- ユーザーに「続けますか」と聞く（Stop Hook が押し戻す）

## 失敗時の挙動

- review agent failure: テレメトリに `agent_failed` を記録しレポート生成して終了
- fix agent failure: 反復ブランチを削除（`git push origin --delete <branch>`、可能なら）してテレメトリ記録・レポート生成・終了
- CI 失敗が 3 回連続: ユーザー判断を仰ぐ（refine と同じ）
- 同じ findings 集合（fingerprint set）が連続 2 反復で完全一致: 「fix が効いていない」と判定して終了。**件数比較ではなく fingerprint 一致で判定するので、fix で新規 finding が生じた場合は集合が違うため継続する**
