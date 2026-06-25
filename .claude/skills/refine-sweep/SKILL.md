---
name: refine-sweep
description: 全コードベースを 4 観点で連続レビューし、ドメイン別並列 PR で critical/major=0 ∧ minor≤5 まで磨く。残 open Issue も自動 /issue-sweep に委譲して実装まで完了。
user-invocable: true
---

# refine-sweep

`/refine` の全コードベース版。特定 PR ではなくリポジトリ全体を対象に `/code-review` / `/doc-drift` / `/spec-audit`（HALT 検知時は `/halt-review`）を並列実行し、critical + major の指摘を 1 PR にまとめて修正・マージするサイクルを回す。

`/refine` は1つの PR を磨くスキル。`/refine-sweep` は **コードベース全体を継続的にゼロ近くへ持っていくスキル**。issue-sweep と同じ CTO + agent 構造、`.sweep/` 配下に状態を残す。

## 引数

- `/refine-sweep` — 全コードベース対象、**critical + major + minor すべて**を fix（デフォルト挙動）
- `/refine-sweep --hard-cap N` — 反復回数の物理上限（デフォルト 30）。基本的に到達しない最終セーフティ。打ち切りは通常 `fix_ineffective`（fingerprint 完全一致が 2 反復連続）で発動する
- `/refine-sweep --no-minor` — minor を fix 対象から外し critical + major のみ修正（軽量モード）
- `/refine-sweep --max-minor N` — minor 残許容数（デフォルト 5、`/refine` と揃えた値。0 を指定すれば完全に磨ききる）
- `/refine-sweep --no-follow-spinoffs` — refine 後の残 open Issue 自動 sweep を抑止（フラグ名は歴史的経緯で残しているが対象は spinoff に限らない全 open Issue）
- `/refine-sweep --max-rounds N` — 残 Issue 追跡の上限周回数（**デフォルト 10、最大 20**）。通常はこの値に到達する前に open Issue が 0 になり自然終了する
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
  "hard_cap_iter": <N>,
  "thresholds": {"critical": 0, "major": 0, "minor": <max_minor>},
  "last_counts": {"critical": <N>, "major": <N>, "minor": <N>},
  "evidence": ["<path>", ...],
  "termination_reason": null | "thresholds_met" | "hard_cap_reached" | "agent_failed" | "fix_ineffective" | "aborted"
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
   jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hc "$hard_cap" --argjson mm "$max_minor" '{
     skill: "refine-sweep",
     started_at: $now, updated_at: $now,
     phase: "iterating", iteration: 0, hard_cap_iter: $hc,
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
6. `start_ts=$(date +%s)`, `iter=0`, `hard_cap=30`, `include_minor=true`, `max_minor=5`, `round=0`, `max_rounds=10`, `follow_spinoffs=true` を初期化（`--no-minor` 指定時のみ `include_minor=false`、`--no-follow-spinoffs` 指定時のみ `follow_spinoffs=false`。`--hard-cap` で hard_cap を上書き可能）
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

**閾値判定（諦めずに hard_cap / fix_ineffective まで粘る方針）:**

```
target_count = critical + major
minor_excess = max(0, minor - max_minor) if include_minor else 0

if target_count == 0 and minor_excess == 0:
  → clean 候補、フェーズ3 へ（フェーズ 3-1 の double-confirm review で最終確定）

elif iter >= hard_cap:
  → hard_cap_reached, フェーズ3 へ（hard cap 到達。fix_ineffective が発動しない異常系の最終セーフティ）

else:
  → 2-5 へ（fix 続行）
```

**ポイント:** 反復の打ち切りは原則 `fix_ineffective`（fingerprint 完全一致が 2 反復連続）に任せる。`hard_cap`（デフォルト 30）は fix_ineffective が発動しないまま延々続いた場合のみ作動する物理上限で、基本的には到達しない。**周回数ベースのソフト上限は持たない**（過去にあった `--max-iter` は廃止）。

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

### 3-0. 残 Issue の自動実装（impl-wt 直接起動方式）

refine 終了時点で **open のままになっている全 Issue** を、refine-sweep のメインスレッドが直接キュー化し、各 Issue を `Agent(claude)` + `/impl-wt` で 1 件ずつ実装する。**`/issue-sweep` はネスト呼びしない**（`.sweep/state.json` を奪い合うため、進捗追跡不能・勝手に terminal 化される問題を回避）。

sweep 中に develop agent が `/spinoff-issue` で作った新規 Issue だけでなく、事前から残っていた Issue も含めて処理対象に入れる（refine で `## 派生 issue` をうまく検知できなかった / ラベルが付かなかった等の検出漏れに対する保険）。

```bash
sweep_start_iso="<フェーズ1 で記録した開始時刻>"
all_open=$(gh issue list --state open --json number,title,createdAt --limit 200)

remaining_ids=$(echo "$all_open" | jq -r '[.[] | .number] | join(" ")')
new_count=$(echo "$all_open" | jq -r --arg since "$sweep_start_iso" '[.[] | select(.createdAt >= $since)] | length')
existing_count=$(echo "$all_open" | jq -r --arg since "$sweep_start_iso" '[.[] | select(.createdAt < $since)] | length')
total=$(( new_count + existing_count ))
```

判定:
- `total == 0` → 3-1 へ
- 1 件以上あり、`--no-follow-spinoffs` 指定なし、`round < max_rounds`:
  - `round += 1` をインクリメント
  - heartbeat 更新: `echo "$PPID:$(date +%s)" > .sweep/lock`
  - 通知 `sweep_notify "refine-sweep: pending issues" "${total} 件 (sweep 中作成 ${new_count} / 既存 ${existing_count}) を impl-wt で処理 (round ${round}/${max_rounds})" ":arrows_counterclockwise:"`
  - **各 Issue を sequential に `Agent(claude)` + `/impl-wt` で実装**:

    ```
    for issue_num in $remaining_ids; do
      echo "$PPID:$(date +%s)" > .sweep/lock   # 各 Issue 処理前に heartbeat

      Agent({
        description: "refine-sweep round <round>: impl-wt #${issue_num}",
        subagent_type: "claude",
        prompt: """
        Issue #${issue_num} を `/impl-wt` で実装・テスト・PR 作成・CI 緑待ち・直接マージ・Issue close まで完了させてください。

        手順:
        1. `Skill(impl-wt, args: "${issue_num}")` で `/impl-wt ${issue_num}` を起動
        2. impl-wt が PR を作成しマージ・close するまで内部で待つ
        3. 完了後に以下の JSON 1 行を最終メッセージとして返す

        成功: {"issue": ${issue_num}, "pr_number": <N>, "merged": true, "closed": true}
        失敗: {"issue": ${issue_num}, "failure": "<理由>", "pr_number": <N or null>}

        厳守事項:
        - `.sweep/state.json` を読まない・書き換えない（refine-sweep のメインスレッドが排他管理しているため）
        - `.sweep/lock` を触らない
        - `/issue-sweep` や `/refine-sweep` を再帰起動しない（state 衝突）
        - JSON 1 行以外を最終メッセージに含めない
        - 内部 log はメインに残さない
        - ユーザー確認で停止しない
        """
      })
    done
    ```

  - 各 agent の JSON を集めて round 結果を記録:

    ```bash
    # round ごとに .sweep/refine-metrics.jsonl に append
    jq -nc \
      --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --argjson round "$round" \
      --argjson merged "$merged_count" \
      --argjson failed "$failed_count" \
      --argjson total "$total" \
      '{ts:$ts, source:"refine-sweep-round", round:$round, total:$total, merged:$merged, failed:$failed}' \
      >> .sweep/refine-metrics.jsonl

    # state.json の evidence にも append
    ev_line=".sweep/refine-metrics.jsonl:$(wc -l < .sweep/refine-metrics.jsonl | tr -d ' ')"
    jq --arg ev "$ev_line" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.evidence += [$ev] | .updated_at = $now' \
       .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
    ```

  - round 完了後、新たな Issue が発生している可能性があるので **3-0 の先頭に戻ってループ**（同じ `round` カウンタを共有して暴走を防ぐ）。`round >= max_rounds` で打ち切り、レポートに未処理 Issue を列挙 + warning 通知
  - 同じ Issue 番号が 2 round 連続で failure になった場合は、その Issue を「stuck」としてスキップし次 round へ進める（永久ループ防止）。stuck Issue は最終レポートに列挙

これにより refine-sweep → 改善 PR → 残 Issue 検出 → impl-wt で実装 → close → 再度 refine-sweep からチェーンする運用が無人化される。`/issue-sweep` を間に挟まないので state.json は常に refine-sweep のものとして整合する。`--no-follow-spinoffs` の名前は歴史的経緯で残しているが、現在の挙動は **spinoff だけでなく全 open issue の自動追跡** を制御する。

### 3-1. 完了処理

1. status 候補を仮置き（`clean` / `hard_cap_reached` / `agent_failed` / `fix_ineffective`）。**`clean` 候補の場合は次ステップの double-confirm review で確定する**。
2. **最終 review 実行（double-confirm 方式、terminal 化前の必須ステップ）**:

   a. **1 回目の最終 review**: 直近の 2-2 から base が動いている可能性があるため、フェーズ2-2 と同じ並列 review をもう一度走らせて `last_counts` を取得。結果を 2-3 と同じ手順で `.sweep/refine-metrics.jsonl` に append し、state.json の `last_counts` と `evidence` を更新（**最低 1 件 evidence が増えていること**）。

   b. **判定とループバック**: 1 回目の最終 review 結果に応じて分岐:
      - `critical + major > 0` または `minor_excess > 0`: **clean ではない**。`hard_cap` 未到達かつ `fix_ineffective` 未発動ならフェーズ2-5 に戻して fix を続行（フェーズ3 を一旦抜けて反復継続）。`hard_cap` 到達済みなら status=`hard_cap_reached` で terminal へ。`fix_ineffective` なら status=`fix_ineffective` で terminal へ。
      - `critical + major == 0` かつ `minor_excess == 0`: clean 候補。**c. の double-confirm review へ進む**。

   c. **2 回目の確認 review（double-confirm）**: clean 候補の場合のみ、もう一度同じ並列 review を走らせる。**fix なしで純粋な再 review**。結果を append し state.json も更新（evidence に最低 1 件追加）。
      - 連続 2 回 0 だった → status=`clean` 確定、ステップ3 へ
      - 2 回目で何か検出された → reviewer のゆらぎ or 検出漏れと判断。1 回目 0 を信用せずフェーズ2-5 に戻して fix 続行（hard_cap 未到達の限り）

   ※ 最終 review 起因でフェーズ2 に戻る場合、戻り先の `iter` は `iter += 1` して通常の反復として扱う。state.json も `phase=iterating` のまま、`termination_reason=null` を維持。

3. `git worktree prune` で残存 worktree 整理
4. **state.json を terminal 化**:
   ```bash
   reason="thresholds_met"   # または hard_cap_reached / agent_failed / fix_ineffective / aborted
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
- **周回数ベースで早期に打ち切る**（過去の `--max-iter` ソフト上限は廃止。打ち切りは原則 `fix_ineffective`、最終セーフティとして `hard_cap` のみ）
- `hard_cap` に到達しても無限ループする
- **最終 review 1 回だけで `clean` を宣言する**（フェーズ 3-1 の double-confirm review で必ず 2 回連続 0 を確認してから terminal 化する。2 回目に検出された場合は 2-5 へ戻す）
- **デフォルトで minor をスキップする**（`--no-minor` 明示時のみ minor 修正を省略可能。それ以外は minor も fix 対象だが、許容数は `max_minor=5` まで残してよい）
- **`.sweep/state.json` を `phase=terminal` にする前に最終 review を再実行せず、推定で `clean` を宣言する**（iter 2 以降のレビューをスキップして「spinoff したから clean だろう」と判定するのは禁止。3-1 ステップ2 で必ず最終 review を走らせる）
- **`.sweep/state.json` の `evidence` 配列が空のままフェーズ3 に進む / terminal 化する**（各反復で最低 1 件追加するルールを破らない）
- レポートに `## Evidence` セクションを書かない（state.json の evidence をそのまま引用する形で必ず残す）
- **残 open Issue の自動 issue-sweep 委譲をスキップする**（`--no-follow-spinoffs` 明示時のみ。それ以外は最大 10 周まで自動で全実装させる、open Issue 0 で自然終了）
- **「残 Issue も追跡しますか？」「次の round に進みますか？」のような確認をユーザーに取る**（デフォルトで全 round 自動継続。`--no-follow-spinoffs` 明示指定時以外、ユーザーに二択を投げない）
- fix agent が `--no-merge` で済ませる（CI 緑後に `gh pr merge --merge --delete-branch` を必ず実行）
- **fix agent が `gh pr merge --auto` を使う**（リポジトリ設定 `allow_auto_merge` に挙動が依存し、OFF だと GraphQL エラーで止まる。CI 緑をポーリングしてから直接マージする方式に統一）
- ユーザーに「続けますか」と聞く（Stop Hook が押し戻す）

## 失敗時の挙動

- review agent failure: テレメトリに `agent_failed` を記録しレポート生成して終了
- fix agent failure: 反復ブランチを削除（`git push origin --delete <branch>`、可能なら）してテレメトリ記録・レポート生成・終了
- CI 失敗が 3 回連続: ユーザー判断を仰ぐ（refine と同じ）
- 同じ findings 集合（fingerprint set）が連続 2 反復で完全一致: 「fix が効いていない」と判定して終了。**件数比較ではなく fingerprint 一致で判定するので、fix で新規 finding が生じた場合は集合が違うため継続する**
