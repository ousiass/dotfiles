---
name: refine-sweep
description: 全コードベースを 4-5 観点でレビューし、指摘を Issue 化 → worktree で消化 → PR/merge/close まで回す。
user-invocable: true
---

# refine-sweep

`/refine-git` の全コードベース版（`/refine` との違いは修正を Issue 化して複数 PR に分ける点）。特定 PR ではなくリポジトリ全体を対象に `/code-review` / `/doc-drift` / `/spec-audit`（HALT 検知時は `/halt-review`、Atomic Design 検知時は `/atomic-review`）を並列実行し、指摘を **GitHub Issue に作成** した上で、sweep が用意した worktree の中で `/impl` を 1 件ずつ走らせて PR → merge → Issue close まで完結させる。

**Issue を可視性の Source of Truth として扱う**。review が Issue を作り、engineer agent が PR → merge → close する。CTO（メインスレッド）は状態管理と反復判定に専念し、コードには触れない。

## 引数

- `/refine-sweep` — critical + major + minor すべてを Issue 化して消化する（デフォルト）
- `/refine-sweep --hard-cap N` — 反復回数の物理上限（デフォルト 30）。基本的に到達しない最終セーフティ
- `/refine-sweep --no-minor` — minor は Issue 化しない（軽量モード）
- `/refine-sweep --max-minor N` — minor 残許容 Issue 数（デフォルト 5、0 なら完全に消化）。minor = `severity:medium` + `severity:low`（フェーズ1 の対応表）
- `/refine-sweep --parallel <N>` — 同時に走る実装 agent 数の上限（デフォルト 5、上限 5）
- `/refine-sweep --max-inflight <M>` — 同時に抱える未マージ PR 数の上限（デフォルト 10、上限 15）
- `/refine-sweep --abort` — 実行中の sweep を中止し lock を削除
- `/refine-sweep --single-pr` — **1 統合ブランチ集約モード**。Issue ごとに PR を作らず統合ブランチ 1 本に積み、最後にベースブランチへ PR を 1 本だけ出す（後述の「single-pr モード」）
- `/refine-sweep --multi-pr` — Issue ごとに PR を作る従来モード
- `/refine-sweep --base <branch>` — ベースブランチ（PR のマージ先）
- `/refine-sweep --branch <name>` — single-pr モードの統合ブランチ名。デフォルト `sweep/refine-sweep-<YYYYmmdd-HHMMSS>`

**`--single-pr` / `--multi-pr` と `--base` は、指定がなければフェーズ P-0 で `AskUserQuestion` で必ず聞く。推測で決めない。**

## 前提

- `git`, `gh` CLI 認証済み
- **GNU coreutils**（`date -d` / `timeout` を使う）。macOS では `brew install coreutils` で `gdate` / `gtimeout` を PATH に置く
- ベースブランチは**フェーズ P-0 でユーザーに確認して確定する**（`../sweep-common/branch-preflight.md`）。`git branch --show-current` の結果を推測でベースに採用しない
- `$SWEEP_DIR/` 書き込み権限
- ラベル `refine-sweep` と `refine-sweep-iter-<N>` を必要に応じて自動作成

## 状態管理 `$SWEEP_DIR/state.json`

sweep 系スキル共通の進行状態ファイル。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**review を再実行せず推定で `phase=terminal` にしてはならない**。terminal 化の直前に最終 review を走らせ、その行が `$SWEEP_DIR/refine-metrics.jsonl` に append されていることを確認する。

**監査証跡は `refine-metrics.jsonl` 一本。** state.json に行番号を写す `evidence` 配列と、review の生カウントを重複保持する `last_counts` は廃止した（issue-sweep と同じ判断。Stop Hook は `phase` と lock の鮮度だけで判定しており、どちらも表示にしか使っていなかった）。

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
  "termination_reason": null | "thresholds_met" | "hard_cap_reached" | "agent_failed" | "fix_ineffective" | "aborted"
}
```

**更新タイミング:**
- フェーズ0/1 開始時に `phase=iterating, iteration=0` で初期化
- 各反復の 2-3（review 直後）で `iteration` を更新（カウント類は `refine-metrics.jsonl` にだけ書く）
- フェーズ3 で `phase=terminal` と `termination_reason` をセット。**直前に最終 review を走らせ、その行が `refine-metrics.jsonl` に append されたことを確認してから terminal 化する**

## single-pr モード（`--single-pr`）

**Issue ごとに PR を作らず、最初に切った統合ブランチ 1 本へ全反復ぶんを積み、最後にベースブランチへ PR を 1 本だけ出す。** 有効時は **`../sweep-common/single-branch-mode.md` を読んでから**フェーズ0 に入る（`skill_name="refine-sweep"`）。フェーズ順は:

`フェーズ0（lock）→ P-0（モード・ベース確定）→ S-0（統合ブランチ作成）→ フェーズ1 → フェーズ2 の反復（S-1 の差分を適用）→ 3-1（double-confirm）→ S-2（統合研磨・最終 PR・CI 確認）→ S-3（レポート）`

通常モードからの差分は以下の箇所だけ:

| 箇所 | single-pr での差し替え |
|---|---|
| P-0 の直後 | S-0 を実行。P-0 で確定したベースから統合ブランチを切って push する |
| フェーズ1 手順1 | `base_branch` は P-0 で確定済み。メイン作業ツリーは統合ブランチに居続ける（`git branch --show-current` から取り直さない） |
| フェーズ0 手順3 の state.json | `mode` / `base_branch` / `int_branch` / `pr_number` / `integrated_count` を追加（S-0-3） |
| 2-1 の base 最新化 | `git pull --ff-only origin "$base_branch"` の代わりに **統合ブランチを進めない**。ベースの更新取り込みが必要なら `git merge --no-ff origin/$base_branch` を明示的に行う |
| 2-2 の review | 変更なし。メイン作業ツリーが統合ブランチなので、反復ごとの review は自動的に「統合済みの状態」を見る |
| 2-5-3 の engineer agent | worktree の分岐元を `$base_branch` から **`$int_branch`** に変える。agent は `/impl #<issue_num> --auto --no-pr` まで（**研磨は回させない** — `/refine-git` は S-2-0 で統合ブランチにまとめて 1 回）。PR 作成・CI 待ち・マージ・Issue close は**すべてやらせない**。返答 JSON は `{"issue":N,"domain":"...","work_branch":"...","worktree":"...","failure":null}` |
| 2-5-4 の判定 | PR 状態の観測ではなく **agent 返答 → 統合 merge**（S-1、必ず直列）。PR が存在しないので 2-5-1 の PR 一覧取得は不要（heartbeat と base 最新化のみ）。`closed_count` は `integrated_count` に読み替える |
| 2-5-5 の Issue close | close しない。**最終 PR は sweep がマージしないので Issue も閉じない**（S-3 で「マージ後に close する Issue」として列挙するだけ）。`fix_ineffective` 判定は open Issue の fingerprint 比較のままだと統合済み Issue が残り続けて誤検知するので、**統合済み Issue を除外した集合**で比較する |
| 3-2 の完了処理 | S-2 → S-3 を実行してからレポートを書く。Summary にモード・ベース・統合ブランチ・PR URL（**open のまま**）を必ず入れる |

## フェーズ0: lock 取得（heartbeat 方式）

**Bash ツールは呼び出しごとに新しいシェル**で、変数も関数も持ち越されない。`$base_branch` / `$int_branch` / `assert_not_base` は **P-0-0 が生成する `$SWEEP_DIR/prelude.sh` から毎回読み直す**（`../sweep-common/branch-preflight.md`）。それらを使う bash スニペットはすべて次の 2 行で始める:

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
source "$SWEEP_DIR/prelude.sh"
```

1. `$SWEEP_DIR/lock` が存在し timestamp が 2 時間以内 → 「他 sweep 実行中」と表示し終了
2. それ以外は `mkdir -p "$SWEEP_DIR" && echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"`
3. `$SWEEP_DIR/state.json` を初期化:
   ```bash
   jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hc "$hard_cap" --argjson mm "$max_minor" '{
     skill: "refine-sweep",
     started_at: $now, updated_at: $now,
     phase: "iterating", iteration: 0, hard_cap_iter: $hc,
     thresholds: {critical: 0, major: 0, minor: $mm},
     termination_reason: null
   }' > "$SWEEP_DIR/state.json"
   ```
4. フェーズ3 / 中断 / `--abort` 時に `rm -f "$SWEEP_DIR/lock"`。**`$SWEEP_DIR/state.json` は残す**（履歴・監査用）が、必ず `phase=terminal` にしてから抜けること

## フェーズ P-0: モードとベースブランチの確定（必須）

**`../sweep-common/branch-preflight.md` を読んでその手順どおりに実行する。スキップ不可。**
`--single-pr` / `--multi-pr` と `--base` の両方が引数で確定している場合のみ、ヒアリング（P-0-2）を省略できる。

ここで確定するもの:

- `mode`（`single-pr` = 統合ブランチ 1 本＋最終 1 PR / `multi-pr` = Issue ごとに PR）
- `base_branch`（PR のマージ先。**`git branch --show-current` の結果を推測で採用しない**）
- `main_worktree` と事前ガード関数 `assert_not_base`

`mode=single-pr` なら続けて S-0 へ、`multi-pr` ならフェーズ1 へ進む。

## フェーズ1: 環境準備

1. `base_branch` は P-0 で確定済み（state.json の `base_branch`）。ここで取り直さない
2. **HALT 検知**:
   - `*.templ` ファイル存在 or 仕様書に「HALT / HTMX+Atomic+Lit+Templ」記述 → `HAS_HALT=true`
3. **Atomic Design 検知**（HAS_HALT=false のみ）:
   - `components/`, `src/components/`, `app/components/` のいずれかに `atoms/` + (`molecules/` or `organisms/`) がある → `HAS_ATOMIC=true`
4. **フロントエンドプロジェクトの Atomic Design 必須ガード**:
   - `package.json` に `react` / `vue` / `next` / `nuxt` の依存が含まれる → `IS_FRONTEND=true`
   - `IS_FRONTEND=true` かつ `HAS_HALT=false` かつ `HAS_ATOMIC=false` → **ここで中断**（`$SWEEP_DIR/state.json` に `termination_reason: "atomic_design_required"` を書き込み、`phase=terminal` にして exit 2）
5. **レビュー対象スキル一覧**:
   - 常に: `code-review`, `doc-drift`, `spec-audit`
   - `HAS_HALT=true`: `halt-review` も追加
   - `HAS_ATOMIC=true`: `atomic-review` も追加
6. **severity ラベルと重要度の対応（唯一の定義。他所で読み替えない）**:

   | 内部用語 | ラベル | マージゲート | `--max-minor` の勘定 |
   |---|---|---|---|
   | critical | `severity:critical` | 0 件必須 | — |
   | major | `severity:high` | 0 件必須 | — |
   | minor | `severity:medium`, `severity:low` | 見ない | 対象 |

   **どのラベルも必ずいずれかのバケツに入る。** 未知の severity 値が来たら minor 扱いにする（ゲートを勝手に厳しくしない）。

7. **ラベル準備**（存在しなければ作成、既存なら何もしない）:
   ```bash
   gh label create refine-sweep --color BB6BD9 --description "created by /refine-sweep" 2>/dev/null || true
   for sev in critical high medium low; do
     gh label create "severity:${sev}" --color EEEEEE 2>/dev/null || true
   done
   ```
8. `start_ts=$(date +%s)`, `iter=0`, `hard_cap=30`, `include_minor=true`, `max_minor=5` を初期化（`--no-minor` 指定時のみ `include_minor=false`、`--hard-cap` / `--max-minor` で上書き可）

## フェーズ2: review → Issue 化 → 消化ループ

### 2-1. 反復冒頭

```bash
source "$SWEEP_DIR/prelude.sh"
echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"          # heartbeat
git fetch origin "$base_branch" 2>/dev/null || true
git pull --ff-only origin "$base_branch" 2>/dev/null || true
iter_label="refine-sweep-iter-$((iter+1))"
gh label create "$iter_label" --color 0E8A16 2>/dev/null || true
```

### 2-2. review 並列実行（Issue 化させる）

各レビュースキルを **Issue 化モードで並列起動**。sub-agent は Skill を呼び出し、Skill 内の `AskUserQuestion` は `GitHub Issue に作成` + `個別 Issue` を自動選択して進む。

```
Agent({
  description: "refine-sweep iter <iter+1> — code-review",
  subagent_type: "claude",
  prompt: """
リポジトリ全体に対して /code-review を Skill ツールで起動して実行してください。

**Issue 化方針（厳守）**:
- 検出した指摘は **GitHub Issue に作成** する（review スキル本来の挙動を活用）
- Skill 内で AskUserQuestion により出力先を聞かれた場合は **「GitHub Issue に作成」** を選択
- Issue の作成方式を聞かれた場合は **「個別 Issue」** を選択（1 指摘 = 1 Issue）
- 承認確認を求められた場合は **承認** して先に進む
- ユーザーへの追加確認で停止しないこと

**Issue に必須で付与するラベル**:
- `refine-sweep`（共通識別）
- `<iter_label>`（今回の反復識別、例: `refine-sweep-iter-3`）
- severity ラベル（`severity:critical` / `severity:high` / `severity:medium` / `severity:low`）
- スキル固有ラベル（例: `code-review`）

`--no-minor` 相当が指示された場合は minor 相当（severity:low）を Issue 化しない。今回の指定: <include_minor>

**返答 JSON（1 行のみ）**:
{"source":"code-review","issue_numbers":[<今回新規作成した Issue 番号>],"counts":{"critical":N,"major":N,"minor":N},"failure":null}

失敗時: {"source":"code-review","issue_numbers":[],"counts":{"critical":0,"major":0,"minor":0},"failure":"<理由>"}

返答ルール:
- JSON 1 行以外を最終メッセージに含めない
- 内部 log をメインに残さない
"""
})

# /doc-drift, /spec-audit も同様（source を差し替え、スキル固有ラベルを doc-drift / spec-audit にする）
# HAS_HALT=true のときのみ /halt-review も同様に並列起動（source="halt-review"）
# HAS_ATOMIC=true のときのみ /atomic-review も同様に並列起動（source="atomic-review"）
```

各 agent の返答を集約:

```bash
new_issues=$(printf '%s\n' "$resp_code" "$resp_doc" "$resp_spec" "$resp_halt" "$resp_atomic" | \
  jq -s 'map(select(. != null and . != "")) | {
    issues: (map(.issue_numbers // []) | flatten | unique),
    counts: {
      critical: (map(.counts.critical // 0) | add),
      major:    (map(.counts.major // 0) | add),
      minor:    (map(.counts.minor // 0) | add)
    },
    by_source: (map({(.source): (.counts // {})}) | add),
    failures: (map(select(.failure != null) | {source, failure}))
  }')

if [[ $(echo "$new_issues" | jq '.failures | length') -gt 0 ]]; then
  # review agent が一つでも failure → agent_failed でフェーズ3 へ
  status="agent_failed"
fi
```

### 2-3. テレメトリ追記 + state.json 更新（review 直後）

```bash
new_issue_count=$(echo "$new_issues" | jq '.issues | length')
open_issue_count=$(gh issue list --label refine-sweep --state open --limit 500 --json number | jq 'length')

jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson iter "$iter" \
  --argjson new_ic "$new_issue_count" \
  --argjson open_ic "$open_issue_count" \
  --argjson counts "$(echo "$new_issues" | jq .counts)" \
  --argjson by_src "$(echo "$new_issues" | jq .by_source)" \
  --argjson halt "$HAS_HALT" \
  '{ts:$ts,source:"refine-sweep-review",iter:$iter,new_issues:$new_ic,open_issues:$open_ic,counts:$counts,by_source:$by_src,halt:$halt}' \
  >> "$SWEEP_DIR/refine-metrics.jsonl"

jq --argjson iter "$iter" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.iteration = $iter | .updated_at = $now' \
   "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
```

**証跡の規則**: 各反復で `refine-metrics.jsonl` に最低 1 行（`source: "refine-sweep-review"`）を append する。**1 行も無いままフェーズ3 に進ませない。**

### 2-4. 閾値判定

**判定材料は open Issue のラベル集計**（review agent が返した「今回の新規件数」ではない。前反復から残っている critical を見落とすため）:

```bash
source "$SWEEP_DIR/prelude.sh"
counts=$(gh issue list --label refine-sweep --state open --limit 500 --json labels \
  | jq -c '[.[] | [.labels[].name]] as $all
    | { critical: ([$all[] | select(index("severity:critical"))] | length),
        major:    ([$all[] | select(index("severity:high"))]     | length),
        minor:    ([$all[] | select(index("severity:critical") or index("severity:high") | not)] | length),
        open:     ($all | length) }')
eval "$(echo "$counts" | jq -r '@sh "critical_open=\(.critical) major_open=\(.major) minor_open=\(.minor) open_issue_count=\(.open)"')"
```

`minor_open` は critical / high 以外の全 open（`severity:medium` / `severity:low` / severity 無し）。**取りこぼしを作らないため、minor は「critical でも major でもないもの」で定義する。**

```
if iter >= hard_cap:
  → hard_cap_reached、フェーズ3 へ

elif critical_open == 0 && major_open == 0
     && (include_minor == false || minor_open <= max_minor)
     && new_issue_count == 0:
  → clean 候補、フェーズ3-1 の double-confirm へ

else:
  → 2-5（Issue 消化）へ
```

`--no-minor` 指定時は minor を Issue 化しないだけで、**過去に作られた minor Issue は判定から除外する**（`include_minor == false` なら `minor_open` を見ない）。

`hard_cap` 到達時のみ物理打ち切り。それ以外は `fix_ineffective` 判定に任せて粘る。

### 2-5. Issue 消化（in-flight パイプライン）

label=`refine-sweep` の全 open Issue を **worktree で消化 → PR → CI 緑 → merge → Issue close** まで完結させる。

**構造は issue-sweep のフェーズ2 と同じ**（バッチが Issue に、ベースブランチが同じ、という対応）。メインスレッドは「キュー操作 / PR 一覧の取得 / agent 起動 / 判定 / マージ / 失敗処理」だけを行い、**実装は必ず `Agent` に丸投げする**。

- `--parallel N`（デフォルト 5、上限 5）= 同時に走る実装 agent の数
- `--max-inflight M`（デフォルト 10、上限 15）= 同時に抱える未マージ PR の数

**wave バリア（「N 件実装 → 全部の CI 待ち → また N 件」）は作らない。** CI が 10 分かかるプロジェクトでは、そのバリアがそのまま「実装 agent が 0 本の 10 分」になる。スロットが空いた瞬間に次の Issue を起動する。

#### 2-5-0. キュー構築とドメイン推定

open Issue を `$SWEEP_DIR/queue.txt` に 1 行 1 Issue で書き出す。各 Issue の本文からファイルパスを抽出（正規表現 `[a-zA-Z0-9_./-]+\.(go|ts|tsx|js|jsx|vue|sql|md|yaml|yml)`）してドメインを推定する:

- `db`: `migrations/`, `schema.sql`, `db/`, `prisma/`
- `backend`: `apps/api/`, `api/`, `src/server/`, `*.go`
- `frontend`: `apps/web/`, `web/`, `src/components/`, `*.tsx`, `*.jsx`, `*.vue`
- `ci`: `.github/workflows/`, `ci/`, `Dockerfile`
- `other`: 上記いずれにもマッチしない or パス抽出不能

**ドメインは並列の可否だけに使う**（2-5-2）。in-flight テーブルは issue-sweep と同じ列に `domain` を足したもので、メッセージ内のテキストとして持ち回る:

| 列 | 内容 |
|---|---|
| `issue` / `domain` / `branch` / `pr` / `stage` / `ci_respawns` / `zero_check_rounds` / `worktree` / `start_ts` | issue-sweep のフェーズ2 と同じ |

#### 2-5-1. ラウンド冒頭（heartbeat / base 最新化 / PR 一覧の一括取得）

```bash
source "$SWEEP_DIR/prelude.sh"
echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"
git fetch origin "$base_branch" 2>/dev/null || true
git pull --ff-only origin "$base_branch" 2>/dev/null || true

# このラウンドで使う PR 情報を **1 コールだけ** で取る（冪等性チェックと状態判定の両方がこれを使う）。
# `head:refine/` で refine-sweep が作った PR だけに絞る
gh pr list --search "head:refine/" --state all --limit 100 \
  --json number,headRefName,state,mergedAt,statusCheckRollup \
  | jq -c '[.[] | {
      pr: .number, branch: .headRefName, state: .state, merged: (.mergedAt != null),
      failed_checks: [.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name],
      waiting: ([.statusCheckRollup[]? | select(.conclusion == null and .status != "COMPLETED")] | length),
      checks_total: ([.statusCheckRollup[]?] | length)
    }]'
```

#### 2-5-2. スロット補充（launch）

`実装中 < N` かつ `in_flight < M` かつキューに**起動可能な** Issue が残っていれば、空きスロット分だけ起動する。

起動可能の条件（ドメインは PR 競合を避けるためだけに使う）:

- **同じドメインの Issue が in-flight に居ない**（同一ドメイン内は直列）
- `db` ドメインは **in-flight が 0 のときだけ**起動する。逆に `db` が in-flight に居る間は他を起動しない
- `refine-sweep-stuck` ラベル付きは起動しない

**冪等性チェック**（2-5-1 の一覧から `branch == "refine/issue-<N>"` を探す。追加の `gh` 呼び出しはしない）:

- `merged == true` → agent を起動せず 2-5-5（close → キュー削除）へ
- `state == "OPEN"` → 既存 PR あり。agent 起動をスキップし、その PR 番号で `stage=ci` として in-flight に載せる
- 見つからない → 2-5-3 で起動

#### 2-5-3. 実装 agent の起動

**worktree は sweep 側が 1 つ作ってからパスを埋めて渡す**（`/impl-wt` を呼ばせない。呼ぶと worktree が二重に作られ、しかも `--no-pr` を持たないので PR が二重に生える）:

```bash
source "$SWEEP_DIR/prelude.sh"
wt="$(dirname "$main_worktree")/$(basename "$main_worktree")-refine-<issue_num>"
git worktree add "$wt" -b "refine/issue-<issue_num>" "$base_branch"   # single-pr なら分岐元は "$int_branch"
assert_not_base "$wt" || { echo "guard 失敗: この Issue は諦める"; }
```

`git worktree add` が失敗したら **その Issue は起動せず** failure 扱いにする（メインリポジトリで代替作業させない）。

```
Agent({
  description: "refine-sweep iter <iter+1> #<issue_num> [<DOMAIN>]",
  subagent_type: "claude",
  prompt: """
Issue #<issue_num> を実装して PR を 1 本作ってください。メインスレッドには JSON だけを返します。
worktree は作成済みです。**以降のすべての作業を <wt の絶対パス> の中で行ってください。**

手順:
0. 作業を始める前に必ず実行する:
   cd <wt の絶対パス>
   cur=$(git rev-parse --abbrev-ref HEAD)
   [[ "$cur" != "<base_branch>" && "$cur" != "main" && "$cur" != "develop" ]] || exit 2
   ここで落ちた場合、**メインリポジトリで代わりに実装してはならない**。failure JSON を返して即座に終了する。
   最初の `git commit` の前にも同じ確認をもう一度行う。
1. `/impl #<issue_num> --auto --no-pr` を Skill ツールで起動して実装する。
   **wt 版（`/impl-wt`）は使わない**（worktree は作成済み。呼ぶと二重に作られる）。
   `--auto` = 確認を取って止まらない / `--no-pr` = PR は手順2 で自分が 1 本だけ作る。
2. push して `gh pr create --base <base_branch>` で PR を 1 本作る。
   `gh pr edit <PR> --add-issue <Issue URL>` でリンクする（`Closes` は使わない）。
3. **PR 作成までで返す。** CI 待ち・マージ・Issue close はメインスレッドの責務なので一切やらない。

成功: {"issue": <issue_num>, "domain": "<DOMAIN>", "pr_number": <N>, "pr_url": "<URL>", "branch": "refine/issue-<N>", "worktree": "<wt の絶対パス>", "failure": null}
失敗: {"issue": <issue_num>, "domain": "<DOMAIN>", "pr_number": null, "worktree": "<wt の絶対パス>", "failure": "<1行で原因>"}

厳守事項:
- `$SWEEP_DIR/state.json` を読まない・書き換えない（refine-sweep のメインスレッドが排他管理しているため）
- `$SWEEP_DIR/lock` を触らない
- `/issue-sweep` や `/refine-sweep` を再帰起動しない（state 衝突）
- **`gh pr merge` を叩かない / `gh issue close` を叩かない**（マージと close はメインスレッド）
- JSON 1 行以外を最終メッセージに含めない
- 内部 log をメインに残さない
- ユーザー確認で停止しない
"""
})
```

#### 2-5-4. 判定と実行（メインスレッド）

**issue-sweep のフェーズ2「判定と実行」の表をそのまま使う**（`merged` / 手動 close / CI 確定失敗 / `checks_total == 0` の猫踏み防止 / マージ / 一覧に見つからない / それ以外）。CI fix agent の起動プロンプトも同じものを使い、branch を `refine/issue-<N>` に差し替えるだけでよい。判定と agent 再起動は **LLM 側で行う**（bash の `while` の中から `Agent` は呼べない）。

#### 2-5-5. Issue close + キュー削除 + metrics

マージ完了後:

```bash
gh issue close "<issue_num>" --comment "Closed by PR #<PR> (via /refine-sweep iter <iter>)" || true
grep -vxF "<issue_num>" "$SWEEP_DIR/queue.txt" > "$SWEEP_DIR/queue.tmp" && mv "$SWEEP_DIR/queue.tmp" "$SWEEP_DIR/queue.txt"
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson iter "$iter" \
   --argjson issue "<issue_num>" --arg domain "<DOMAIN>" --argjson pr "<PR>" --arg status "merged" \
   '{ts:$ts,source:"refine-sweep-consume",iter:$iter,issue:$issue,domain:$domain,pr_number:$pr,status:$status}' \
   >> "$SWEEP_DIR/refine-metrics.jsonl"
```

#### 2-5-6. worktree 掃除

agent が返した `worktree` パスをそのまま消す（`failure` のときも**必ず**消す。次反復で同じ Issue を再試行するとき名前が衝突する）:

```bash
git worktree remove --force "<worktree>" 2>/dev/null || true
```

#### 2-5-7. 失敗時（stuck 判定）

agent が `failure` を返した / CI を諦めた Issue は、その反復では**諦めてキューから消す**（1 反復 = 1 Issue あたり 1 回の試行。残すと Stop Hook が永久に停止をブロックする）。metrics に `status` を記録し、失敗 Issue 番号を反復ごとのファイルに残す:

```bash
echo "$failed_ids" > "$SWEEP_DIR/failed-iter-${iter}.txt"
prev="$SWEEP_DIR/failed-iter-$((iter-1)).txt"
if [[ -f "$prev" ]]; then
  # 2 反復連続で失敗した Issue は stuck としてラベル付与し、次反復から除外する
  for id in $(comm -12 <(sort "$prev") <(sort "$SWEEP_DIR/failed-iter-${iter}.txt")); do
    gh issue edit "$id" --add-label "refine-sweep-stuck" 2>/dev/null || true
  done
fi
```

#### 2-5-8. 待機と反復の終了

このラウンドで何も進捗がなく（マージ 0 件・新規起動 0 件）、in-flight が残っている場合のみ **1 つの bash コマンドの中で `sleep 60`** してから 2-5-1 に戻る。進捗があった場合は待たずに次のラウンドへ進む。

**「待機。」と言ってターンを終えてはならない**（Stop Hook に押し戻されるたびにモデルのターンを 1 回消費する）。

**キューが空 ∧ in-flight が 0 になったらこの反復は終了**。`closed_count` / `failed_ids` を確定させて下記の fix_ineffective 判定に進む。

**fix_ineffective 判定（Issue の fingerprint set 比較）**:

各反復終了時に、label=`refine-sweep` かつ label≠`refine-sweep-stuck` の open Issue の fingerprint set を保存し、前反復と比較する:

```bash
gh issue list --label refine-sweep --state open --limit 500 --json number,title,body,labels \
  | jq -c '[.[] | select((.labels // []) | map(.name) | index("refine-sweep-stuck") | not)
           | (.title + "|" + (.body // "" | tostring))] | sort | unique' \
  > "$SWEEP_DIR/issues-iter-${iter}.json"

prev_file="$SWEEP_DIR/issues-iter-$((iter-1)).json"
if [[ "$iter" -ge 1 && -f "$prev_file" ]]; then
  curr=$(cat "$SWEEP_DIR/issues-iter-${iter}.json")
  prev=$(cat "$prev_file")
  if [[ "$curr" == "$prev" && "$curr" != "[]" ]]; then
    status="fix_ineffective"
    break
  fi
fi
```

- 前反復と Issue 集合が完全一致 → 打ち切り（消化が本当に効いてない）
- 消化で 3 件 close、新規 review で 3 件発見（title/body が違う）→ 集合が違うので**継続**
- 件数だけで判定しない（fingerprint 一致のみで打ち切り）

`iter += 1` して 2-1 へ戻る。

## フェーズ3: 完了処理

### 3-1. double-confirm review（clean 候補時のみ）

clean 候補（`open_issue_count == 0 && new_issue_count == 0` または minor 許容範囲内）の場合、**もう一度 2-2 と同じ並列 review を走らせる**（consume なしの純粋な再 review）:

- 結果を `$SWEEP_DIR/refine-metrics.jsonl` に append する（この行が「最終 review を実際に走らせた」証跡になる）
- 連続 2 回とも新規 Issue = 0 → status=`clean` 確定、3-2 へ
- 2 回目で新規 Issue が出た → reviewer のゆらぎ or 検出漏れ。1 回目の 0 を信用せずフェーズ2-5 に戻して消化（`hard_cap` 未到達の限り、`iter += 1`）

### 3-2. 完了処理

1. `git worktree prune` で残存 worktree 整理
2. **state.json を terminal 化**:
   ```bash
   reason="thresholds_met"   # または hard_cap_reached / agent_failed / fix_ineffective / aborted
   jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
     "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
   ```
3. レポート生成 `$SWEEP_DIR/report-refine-sweep-<ts>.md`（**`## Evidence` セクション必須**）:

```bash
source "$SWEEP_DIR/prelude.sh"
ts=$(date -u +%Y%m%dT%H%M%SZ)
report="$SWEEP_DIR/report-refine-sweep-${ts}.md"
mkdir -p "$SWEEP_DIR"
# 反復カウンタ・開始時刻はシェルに残らない。state.json から読む
eval "$(jq -r '@sh "iter=\(.iteration) started_at=\(.started_at) reason=\(.termination_reason // "-")"' "$SWEEP_DIR/state.json")"
elapsed=$(( $(date +%s) - $(date -d "$started_at" +%s) ))
{
  echo "# refine-sweep report — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Summary"
  echo "- Base branch: ${base_branch}"
  echo "- Iterations: ${iter}"
  echo "- Final status: **${status}** (reason: ${reason})"
  echo "- Elapsed: ${elapsed}s"
  echo
  echo "## Issue trend"
  echo
  echo "| Iter | New | Closed | Open (end) | Critical | Major | Minor |"
  echo "|---|---|---|---|---|---|---|"
  jq -rs '(map(select(.source == "refine-sweep-consume")) | INDEX(.iter | tostring)) as $c
    | map(select(.source == "refine-sweep-review"))[]
    | "| \(.iter) | \(.new_issues) | \($c[.iter | tostring].closed // "-") | \(.open_issues) | \(.counts.critical) | \(.counts.major) | \(.counts.minor) |"' "$SWEEP_DIR/refine-metrics.jsonl"
  echo
  echo "## Evidence（review 実行の証跡）"
  echo
  jq -r 'select(.source == "refine-sweep-review") | "- iter \(.iter) @ \(.ts): new=\(.new_issues) open=\(.open_issues)"' "$SWEEP_DIR/refine-metrics.jsonl"
  echo
  echo "## Remaining open issues"
  gh issue list --label refine-sweep --state open --limit 500 --json number,title,labels \
    | jq -r '.[] | "- #\(.number) \(.title) [labels: \((.labels // []) | map(.name) | join(", "))]"'
  echo
  echo "## Stuck issues (skipped after 2 consecutive failures)"
  gh issue list --label refine-sweep-stuck --state open --limit 500 --json number,title \
    | jq -r '.[] | "- #\(.number) \(.title)"'
} > "$report"
```

4. `rm -f "$SWEEP_DIR/lock"`（state.json は terminal のまま残す）
5. 通知: `sweep_notify "refine-sweep done" "${iter} iters, status=${status}, report: ${report}" ":checkered_flag:"`
6. ユーザーにレポートパスを返す

## 禁止行動

**本文の手順に書いてあることは再掲しない。** ここにあるのは「手順どおりに読んでも踏みうる罠」だけ。

**ブランチ**

- **`git branch --show-current` の結果を推測でベースブランチに採用する**（起点はユーザーが決める）
- **事前ガードに引っかかった状態を `git reset` / `git checkout -f` で自動的に直して続行する**（人に返す）
- **シェル変数（`$base_branch` / `$iter` / `$start_ts` 等）が次の Bash 呼び出しまで残ると仮定する**（毎回新しいシェル。prelude を source し、カウンタは state.json から読む）

**agent への委譲**

- **メインスレッド自身がコードを修正する / コミットする / PR を編集する**（CTO は実装に触らない）
- **メインが CI 緑後にマージするのを忘れる / マージ完了を確認せず in-flight から外す**（agent は PR 作成までで返るので、メインが観測しないと PR が埋もれる）
- **Issue を close せずに PR merge で済ませる**（メインが merge 直後に `gh issue close` を必ず実行する）
- **agent プロンプトに埋められないプレースホルダ（`<worktree_path>` 等）を残す**（agent がガードを実行できず、ベースブランチ直コミットの検知が丸ごと落ちる）
- **review agent に Issue 作成を止めさせる**（旧設計。現在は Issue 化が意図的設計）
- **`checks_total == 0` を「CI 緑」とみなしてマージする**（PR 作成直後は check が 1 つも登録されていない。2 ラウンド連続 0 件を確認してから CI 無しと判定する）
- **やることが無いときにターンを終えて待つ**（Stop Hook に押し戻されるたびにモデルのターンを 1 回消費する。待つときは 1 つの bash コマンドの中で `sleep 60` を挟む）

**反復と終了**

- **周回数ベースで早期に打ち切る**（打ち切りは `fix_ineffective` か `hard_cap` のみ）／ `hard_cap` に到達しても無限ループする
- **デフォルトで minor をスキップする**（`--no-minor` 明示時のみ）
- **`phase=terminal` にする前に最終 review を再実行しない**
- **state.json に `evidence` / `last_counts` を復活させる**（証跡は `refine-metrics.jsonl` 一本。二重管理すると片方だけ更新される）／ レポートに `## Evidence` セクションを書かない
- **`refine-sweep-stuck` ラベルを勝手に外す**（人手判断が入るまで維持）
- **ユーザーに確認を取って止まる**（「続けますか」「次の反復に進みますか」「並列度はいくつに？」。すべてデフォルトで進める。Stop Hook が押し戻す）

**single-pr モード**

- `--single-pr` 指定時に `../sweep-common/single-branch-mode.md` を読まずに進める（差分表だけで手順を推測しない）
- **Issue ごとに PR を作る / 統合 merge を並列に走らせる / 統合のたびに CI を待つ**（詳細は同 reference の禁止行動）

## 失敗時の挙動

- review agent failure（1 つでも `failure != null` を返す）: `agent_failed` を記録しフェーズ3 へ
- engineer agent failure が 2 反復連続で同じ Issue: `refine-sweep-stuck` ラベルを付与し次反復から除外して継続
- 全 open Issue が stuck: レポートに列挙して terminal 化
- 同じ Issue 集合（fingerprint set）が連続 2 反復完全一致: `fix_ineffective` で終了
