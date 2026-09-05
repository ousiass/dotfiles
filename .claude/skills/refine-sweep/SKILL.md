---
name: refine-sweep
description: 全コードベースを 4-5 観点でレビューし、指摘を Issue 化 → impl-wt で消化 → close まで一連で回す。critical/major=0 ∧ minor 残 Issue ≤ 閾値になるまで反復する。
user-invocable: true
---

# refine-sweep

`/refine-git` の全コードベース版（`/refine` との違いは修正を Issue 化して複数 PR に分ける点）。特定 PR ではなくリポジトリ全体を対象に `/code-review` / `/doc-drift` / `/spec-audit`（HALT 検知時は `/halt-review`、Atomic Design 検知時は `/atomic-review`）を並列実行し、指摘を **GitHub Issue に作成** した上で `/impl-wt` で 1 件ずつ消化し PR → merge → Issue close まで完結させる。

**Issue を可視性の Source of Truth として扱う**。review が Issue を作り、impl-wt が PR → merge → close する。CTO（メインスレッド）は状態管理と反復判定に専念し、コードには触れない。

## 引数

- `/refine-sweep` — critical + major + minor すべてを Issue 化して消化する（デフォルト）
- `/refine-sweep --hard-cap N` — 反復回数の物理上限（デフォルト 30）。基本的に到達しない最終セーフティ
- `/refine-sweep --no-minor` — minor は Issue 化しない（軽量モード）
- `/refine-sweep --max-minor N` — minor 残許容 Issue 数（デフォルト 5、0 なら完全に消化）
- `/refine-sweep --abort` — 実行中の sweep を中止し lock を削除
- `/refine-sweep --single-pr` — **1 統合ブランチ集約モード**。Issue ごとに PR を作らず統合ブランチ 1 本に積み、最後にベースブランチへ PR を 1 本だけ出す（後述の「single-pr モード」）
- `/refine-sweep --multi-pr` — Issue ごとに PR を作る従来モード
- `/refine-sweep --base <branch>` — ベースブランチ（PR のマージ先）
- `/refine-sweep --branch <name>` — single-pr モードの統合ブランチ名。デフォルト `sweep/refine-sweep-<YYYYmmdd-HHMMSS>`

**`--single-pr` / `--multi-pr` と `--base` は、指定がなければフェーズ P-0 で `AskUserQuestion` で必ず聞く。推測で決めない。**

## 前提

- `git`, `gh` CLI 認証済み
- ベースブランチは**フェーズ P-0 でユーザーに確認して確定する**（`~/.claude/skills/issue-sweep/references/branch-preflight.md`）。`git branch --show-current` の結果を推測でベースに採用しない
- `.sweep/` 書き込み権限
- ラベル `refine-sweep` と `refine-sweep-iter-<N>` を必要に応じて自動作成

## 状態管理 `.sweep/state.json`

sweep 系スキル共通の進行状態ファイル。Stop Hook (`check-sweep-state.sh`) は `phase != "terminal"` の間（lock が新鮮な限り）停止をブロックする。**review を再実行せず推定で `phase=terminal` にしてはならない**。terminal 化前に必ず最終 review を走らせ、その出力パスを `evidence` に append する。

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
  "last_counts": {
    "critical": <N>, "major": <N>, "minor": <N>,
    "new_issues": <N>, "open_issues": <N>, "closed_this_iter": <N>
  },
  "evidence": ["<path>", ...],
  "termination_reason": null | "thresholds_met" | "hard_cap_reached" | "agent_failed" | "fix_ineffective" | "aborted"
}
```

**更新タイミング:**
- フェーズ0/1 開始時に `phase=iterating, iteration=0, evidence=[]` で初期化
- 各反復の 2-3（review 直後）と 2-5 末尾（Issue 消化直後）で `iteration`, `last_counts`, `evidence` を更新
- フェーズ3 で `phase=terminal` と `termination_reason` をセット。**直前に最終 review を走らせ evidence を追加してから terminal 化する**

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
| 2-5 の engineer agent | `/impl-wt` を呼ばせない。**sweep 側が `$int_branch` から worktree を作り**、agent は `/impl #<issue_num> --auto --no-pr` まで（**研磨は回させない** — `/refine-git` は S-2-0 で統合ブランチにまとめて 1 回）。PR 作成・CI 待ち・マージ・Issue close は**すべてやらせない**。返答 JSON は `{"issue":N,"domain":"...","work_branch":"...","worktree":"...","failure":null}` |
| 2-5 の集約 | agent 返答ごとに **メインスレッドが統合 merge**（S-1、必ず直列）。`closed_count` は `integrated_count` に読み替える |
| 2-5 の Issue close | close しない。**最終 PR は sweep がマージしないので Issue も閉じない**（S-3 で「マージ後に close する Issue」として列挙するだけ）。`fix_ineffective` 判定は open Issue の fingerprint 比較のままだと統合済み Issue が残り続けて誤検知するので、**統合済み Issue を除外した集合**で比較する |
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
     last_counts: {critical: null, major: null, minor: null, new_issues: null, open_issues: null, closed_this_iter: null},
     evidence: [],
     termination_reason: null
   }' > .sweep/state.json
   ```
4. フェーズ3 / 中断 / `--abort` 時に `rm -f .sweep/lock`。**`.sweep/state.json` は残す**（履歴・監査用）が、必ず `phase=terminal` にしてから抜けること

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
   - `IS_FRONTEND=true` かつ `HAS_HALT=false` かつ `HAS_ATOMIC=false` → **ここで中断**（`.sweep/state.json` に `termination_reason: "atomic_design_required"` を書き込み、`phase=terminal` にして exit 2）
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
7. `start_ts=$(date +%s)`, `iter=0`, `hard_cap=30`, `include_minor=true`, `max_minor=5` を初期化（`--no-minor` 指定時のみ `include_minor=false`、`--hard-cap` / `--max-minor` で上書き可）

## フェーズ2: review → Issue 化 → impl-wt 消化ループ

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
  >> .sweep/refine-metrics.jsonl

ev_line=".sweep/refine-metrics.jsonl:$(wc -l < .sweep/refine-metrics.jsonl | tr -d ' ')"
jq --argjson iter "$iter" \
   --argjson counts "$(echo "$new_issues" | jq .counts)" \
   --argjson new_ic "$new_issue_count" \
   --argjson open_ic "$open_issue_count" \
   --arg ev "$ev_line" \
   --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
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
   '.iteration = $iter
    | .last_counts = ($counts + {new_issues: $new_ic, open_issues: $open_ic, closed_this_iter: 0})
    | .evidence += [$ev]
    | .updated_at = $now' \
   .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
```

**evidence の append 規則**: 各反復で最低 1 件追加。空のままフェーズ3 に進ませない。

### 2-4. 閾値判定

```

`minor_open` は critical / high 以外の全 open（`severity:medium` / `severity:low` / severity 無し）。**取りこぼしを作らないため、minor は「critical でも major でもないもの」で定義する。**

elif iter >= hard_cap:
  → hard_cap_reached, フェーズ3 へ
`--no-minor` 指定時は minor を Issue 化しないだけで、**過去に作られた minor Issue は判定から除外する**（`include_minor == false` なら `minor_open` を見ない）。


elif critical_open == 0 && major_open == 0
     && (include_minor == false || minor_open <= max_minor)
     && new_issue_count == 0:
  → clean 候補、フェーズ3-1 の double-confirm へ

else:
  → 2-5（Issue 消化）へ
```

`hard_cap` 到達時のみ物理打ち切り。それ以外は `fix_ineffective` 判定に任せて粘る。

### 2-5. Issue 消化（impl-wt 並列起動）

label=`refine-sweep` の全 open Issue を **`/impl-wt` で消化 → PR → CI 緑 → merge → Issue close** まで完結させる。メインスレッドは Issue キューを組み、engineer agent を wave 分割で並列起動して JSON だけ受け取る。

**wave 分割ポリシー**:
1. 各 Issue の本文からファイルパスを抽出（正規表現 `[a-zA-Z0-9_./-]+\.(go|ts|tsx|js|jsx|vue|sql|md|yaml|yml)`）
2. パスからドメイン推定:
   - `db`: `migrations/`, `schema.sql`, `db/`, `prisma/`
   - `backend`: `apps/api/`, `api/`, `src/server/`, `*.go`
   - `frontend`: `apps/web/`, `web/`, `src/components/`, `*.tsx`, `*.jsx`, `*.vue`
   - `ci`: `.github/workflows/`, `ci/`, `Dockerfile`
   - `other`: 上記いずれにもマッチしない or パス抽出不能
3. **第 1 wave**: `db` ドメインの Issue のみ sequential
4. **第 2 wave**: `backend` / `frontend` / `ci` / `other` を **各ドメイン内は sequential、ドメイン間は並列**（同一ドメインで PR 競合を避ける）
5. wave 完了ごとに `git fetch && git pull --ff-only` で base を最新化してから次 wave

各 Issue の engineer agent プロンプト:

```
Agent({
  description: "refine-sweep iter <iter+1> impl-wt #<issue_num> [<DOMAIN>]",
  subagent_type: "claude",
  prompt: """
Issue #<issue_num> を実装 → PR 作成 → CI 緑待ち → merge → Issue close まで完了させてください。

手順:
1. `Skill(impl-wt, args: "#<issue_num>")` で impl-wt を起動し、worktree での実装と PR 作成まで完了させる（impl-wt 自体は PR 作成で止まる設計）。
   impl-wt が worktree を作った直後に、そこで**必ず**確認する:
   cur=$(git -C <worktree_path> rev-parse --abbrev-ref HEAD)
   [[ "$cur" != "<base_branch>" && "$cur" != "main" && "$cur" != "develop" ]] || exit 2
   worktree が作られなかった / ベースブランチのままだった場合は、**メインリポジトリで代わりに実装してはならない**。
   failure JSON を返して即座に終了する
2. impl-wt が返した PR 番号を保持
3. CI 緑を待つ。**「待機。」と言ってターンを終えて待たない** — 1 つの bash コマンドの中で `sleep` を挟んでブロックする:
   timeout 3600 bash -c 'while :; do pending=$(gh pr view <PR> --json statusCheckRollup --jq "[.statusCheckRollup[]? | select(.conclusion == null and .status != \"COMPLETED\")] | length"); [ "${pending:-0}" -eq 0 ] && break; sleep 60; done'
   待機が明けたら `gh pr view <PR> --json state,statusCheckRollup` を 1 回だけ叩いて判定:
   - 全 check 完了 ∧ FAILURE なし ∧ state=OPEN → `gh pr merge <PR> --merge --delete-branch` を実行
   - FAILURE あり ∧ pending=0 → impl-wt を再起動して修正 push（最大 3 回まで）
   - state=MERGED になったら完了
4. merge 成功後、`gh issue close #<issue_num> --comment "Closed by PR #<PR> (via /refine-sweep iter <iter>)"` で Issue を明示的に close
5. 完了後に以下の JSON 1 行を最終メッセージとして返す

成功: {"issue": <issue_num>, "domain": "<DOMAIN>", "pr_number": <N>, "merged": true, "closed": true, "failure": null}
失敗: {"issue": <issue_num>, "domain": "<DOMAIN>", "pr_number": <N or null>, "merged": false, "closed": false, "failure": "<理由>"}

厳守事項:
- `.sweep/state.json` を読まない・書き換えない（refine-sweep のメインスレッドが排他管理しているため）
- `.sweep/lock` を触らない
- `/issue-sweep` や `/refine-sweep` を再帰起動しない（state 衝突）
- `gh pr merge --auto` を使わない（CI 緑ポーリング → 直接マージ方式に統一）
- impl-wt が `Closes #N` を使わない設計なので、merge 後の `gh issue close` を必ず自分で実行する
- JSON 1 行以外を最終メッセージに含めない
- 内部 log をメインに残さない
- ユーザー確認で停止しない
"""
})
```

**集約とループ制御**:

```bash
# 各 wave で並列起動した agent の JSON を集約
closed_count=$(echo "$wave_results" | jq '[.[] | select(.closed == true)] | length')
failed_ids=$(echo "$wave_results" | jq -r '[.[] | select(.failure != null) | .issue] | join(" ")')

# stuck 判定（同じ issue が 2 反復連続で failure）
prev_failed_file=".sweep/failed-iter-$((iter-1)).txt"
curr_failed_file=".sweep/failed-iter-${iter}.txt"
echo "$failed_ids" > "$curr_failed_file"
if [[ -f "$prev_failed_file" ]]; then
  stuck=$(comm -12 <(sort "$prev_failed_file") <(sort "$curr_failed_file"))
  if [[ -n "$stuck" ]]; then
    # 2 反復連続 failure の Issue は「stuck」としてラベル付与し次反復から除外
    for id in $stuck; do
      gh issue edit "$id" --add-label "refine-sweep-stuck" 2>/dev/null || true
    done
  fi
fi

# state.json の closed_this_iter を更新
jq --argjson closed "$closed_count" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.last_counts.closed_this_iter = $closed | .updated_at = $now' \
   .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
```

**fix_ineffective 判定（Issue の fingerprint set 比較）**:

各反復終了時に、label=`refine-sweep` かつ label≠`refine-sweep-stuck` の open Issue の fingerprint set を保存し、前反復と比較する:

```bash
gh issue list --label refine-sweep --state open --limit 500 --json number,title,body \
  | jq -c '[.[] | select((.labels // []) | map(.name) | index("refine-sweep-stuck") | not)
           | (.title + "|" + (.body // "" | tostring))] | sort | unique' \
  > ".sweep/issues-iter-${iter}.json"

prev_file=".sweep/issues-iter-$((iter-1)).json"
if [[ "$iter" -ge 1 && -f "$prev_file" ]]; then
  curr=$(cat ".sweep/issues-iter-${iter}.json")
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

- 結果を `.sweep/refine-metrics.jsonl` に append し、state.json の `last_counts` / `evidence` を更新（evidence に最低 1 件追加）
- 連続 2 回とも新規 Issue = 0 → status=`clean` 確定、3-2 へ
- 2 回目で新規 Issue が出た → reviewer のゆらぎ or 検出漏れ。1 回目の 0 を信用せずフェーズ2-5 に戻して消化（`hard_cap` 未到達の限り、`iter += 1`）

### 3-2. 完了処理

1. `git worktree prune` で残存 worktree 整理
2. **state.json を terminal 化**:
   ```bash
   reason="thresholds_met"   # または hard_cap_reached / agent_failed / fix_ineffective / aborted
   jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
     .sweep/state.json > .sweep/state.json.tmp && mv .sweep/state.json.tmp .sweep/state.json
   ```
3. レポート生成 `.sweep/report-refine-sweep-<ts>.md`（**`## Evidence` セクション必須**）:

```bash
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
  echo "- Elapsed: $(( $(date +%s) - start_ts ))s"
  echo
  echo "## Issue trend"
  echo
  echo "| Iter | New | Closed | Open (end) | Critical | Major | Minor |"
  echo "|---|---|---|---|---|---|---|"
  jq -r 'select(.source == "refine-sweep-review") | "| \(.iter) | \(.new_issues) | ? | \(.open_issues) | \(.counts.critical) | \(.counts.major) | \(.counts.minor) |"' .sweep/refine-metrics.jsonl
  echo
  echo "## Evidence"
  echo
  jq -r '.evidence[] | "- \(.)"' .sweep/state.json
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

4. `rm -f .sweep/lock`（state.json は terminal のまま残す）
5. 通知: `sweep_notify "refine-sweep done" "${iter} iters, status=${status}, report: ${report}" ":checkered_flag:"`
6. ユーザーにレポートパスを返す

## 禁止行動

**ブランチ**

- **フェーズ P-0 を飛ばす / モードとベースブランチを聞かずに始める**（`~/.claude/skills/issue-sweep/references/branch-preflight.md`）
- **`git branch --show-current` の結果を推測でベースブランチに採用する**
- **worktree を作らずメインリポジトリで実装する**（ベースブランチ直コミットの主因。worktree が無いなら failure を返して諦める）
- **事前ガードに引っかかった状態を `git reset` / `git checkout -f` で自動的に直して続行する**（人に返す）

**その他**

- **メインスレッド自身がコードを修正する / コミットする / PR を編集する**（CTO は実装に触らない）
- **メインスレッドで PR マージ完了のポーリングや CI fix ループを直接回す**（impl-wt agent 内に閉じ込める）
- **review agent に Issue 作成を止めさせる**（旧設計。現在は Issue 化が意図的設計）
- **fix agent が `Skill(impl-wt)` を呼ばず自前で PR を作る**（impl-wt に一任することでフローを統一）
- **fix agent が `gh pr merge --auto` を使う**（CI 緑ポーリング → 直接 `--merge` に統一）
- **fix agent が Issue を close せずに PR merge で済ませる**（`Closes #N` 記法 or 明示的な `gh issue close` で必ず close）
- **周回数ベースで早期に打ち切る**（打ち切りは `fix_ineffective` か `hard_cap` のみ）
- `hard_cap` に到達しても無限ループする
- **最終 review 1 回だけで `clean` を宣言する**（3-1 の double-confirm で 2 回連続 0 を確認してから terminal 化）
- **デフォルトで minor をスキップする**（`--no-minor` 明示時のみ）
- **`.sweep/state.json` を `phase=terminal` にする前に最終 review を再実行しない**
- **`.sweep/state.json` の `evidence` 配列が空のままフェーズ3 に進む / terminal 化する**
- レポートに `## Evidence` セクションを書かない
- **`refine-sweep-stuck` ラベルを勝手に外す**（人手判断が入るまで維持）
- ユーザーに「続けますか」「次の wave に進みますか」を聞く（Stop Hook が押し戻す）

**single-pr モード**

- `--single-pr` 指定時に `~/.claude/skills/issue-sweep/references/single-branch-mode.md` を読まずに進める（差分表だけで手順を推測しない）
- **Issue ごとに PR を作る / 統合 merge を並列に走らせる / 統合のたびに CI を待つ**（詳細は same reference の禁止行動）
- **やることが無いときにターンを終えて待つ**（Stop Hook に押し戻されるたびにモデルのターンを 1 回消費する。実測で 1 セッション 1 万往復、トランスクリプトの 10% がフック文言だった。待つときは必ず 1 つの bash コマンドの中で `sleep 60` を挟んでブロックする）
- **single-pr で engineer agent に `/impl-wt` を呼ばせる**（worktree は sweep が統合ブランチから作る。呼ぶと二重に作られ、しかも `--no-pr` を持たないので PR が生える）

## 失敗時の挙動

- review agent failure（1 つでも `failure != null` を返す）: `agent_failed` を記録しフェーズ3 へ
- impl-wt agent failure が 2 反復連続で同じ Issue: `refine-sweep-stuck` ラベルを付与し次反復から除外して継続
- 全 open Issue が stuck: レポートに列挙して terminal 化
- 同じ Issue 集合（fingerprint set）が連続 2 反復完全一致: `fix_ineffective` で終了
source "$SWEEP_DIR/prelude.sh"
- **シェル変数（`$base_branch` / `$iter` / `$start_ts` 等）が次の Bash 呼び出しまで残ると仮定する**（毎回新しいシェル。prelude を source し、カウンタは state.json から読む）
