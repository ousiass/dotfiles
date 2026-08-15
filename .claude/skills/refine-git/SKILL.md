---
name: refine-git
description: gitリモートとの差分を対象に review→修正→再review を反復し研磨後、CI 緑を待って直接マージし Issue close まで実行する。
user-invocable: true
---

# refine-git

`refine` の差分版。review → 修正 → 再 review を回し、**PR の差分だけ**をレビュー観点で「軽微指摘のみ」状態まで持っていく。

`impl` / `impl-wt` / `issue-sweep` が作った PR を磨く用途はすべてこちら。差分外の既存問題まで拾うと閾値に永久到達せず、PR と無関係なファイルまで修正してしまうため。

| スキル | 対象 | 修正の流し方 |
|---|---|---|
| **refine-git**（本スキル） | PR の差分のみ | PR ブランチ上で直接修正 |
| `refine` | リポジトリ全体 | PR ブランチ上で直接修正（1 PR にまとめる） |
| `refine-sweep` | リポジトリ全体 | Issue 化 → `impl-wt` で消化（複数 PR） |

## 引数

- `/refine-git` — 現在のブランチ / PR を対象
- `/refine-git #<PR番号>` — 特定 PR を対象
- `/refine-git --max-minor <N>` — minor 指摘の上限（デフォルト 5）
- `/refine-git --max-iter <N>` — レビューループ反復上限（デフォルト 10）
- `/refine-git --no-merge` — 研磨のみでマージしない（デフォルトは CI 緑を待って直接マージまで実行）

## 前提

- `git`, `gh` CLI 認証済み
- 対象 PR / ブランチが checkout 可能
- `.sweep/` ディレクトリへの書き込み権限（テレメトリ用）

## フェーズ1: セットアップと差分スコープの確定

`skill_name="refine-git"` を設定し、`refine` の `references/common-setup.md` の手順 1〜7 を実行する（ターゲット特定・worktree 確保・変数初期化・state.json 初期化・HALT / Atomic Design 検知・フロントエンドガード）。

状態管理の仕様は `refine` の `references/state-and-telemetry.md` を参照。

### 1-8. 差分スコープの確定（本スキル固有・必須）

worktree 確保の直後に、比較先と変更ファイル一覧を必ず確定する:

```bash
# 比較先は PR の baseRefName（PR がない場合は origin/develop、無ければ origin/main）
base_ref="origin/${base_branch:-develop}"
git rev-parse --verify "$base_ref" >/dev/null 2>&1 || base_ref="origin/main"

git fetch origin
merge_base=$(git merge-base "$base_ref" HEAD)
changed_files=$(git diff --name-only "$merge_base"...HEAD)

if [[ -z "$changed_files" ]]; then
  echo "ERROR: $base_ref との差分が空です。refine-git の対象がありません。"
  exit 2
fi

scope_label="\`${base_ref}...HEAD\` の差分のみ（$(printf '%s\n' "$changed_files" | wc -l) files）"
```

`base_ref` / `merge_base` は全反復で使い回す。`changed_files` は**修正 push のたびに再取得する**。

### 1-9. レビュー対象スキル一覧の決定（すべて差分スコープ版）

- 常に: `code-review-git`, `doc-drift-git`, `spec-audit-git`
- `HAS_HALT=true` のみ: `halt-review` を追加（**変更ファイルのパスを引数で渡す**）
- `HAS_ATOMIC=true` のみ: `atomic-review` を追加（**変更ファイルのパスを引数で渡す**）

`halt-review` / `atomic-review` には差分版が存在しないため、`changed_files` のうち各スキルの対象拡張子（`.templ` / `.go` / `.ts` / `.tsx` / `.vue` 等）に該当するパスだけを引数として渡し、走査範囲を差分に限定する。該当パスが 0 件ならそのスキルは起動しない。

## フェーズ2: review → 修正ループ

各反復で `Agent(subagent_type=claude)` を**レビュースキルごとに並列起動**。**メインスレッドはコードに触れない**。

### 2-1. レビュー集約（並列）

決定したスキル群を**同一メッセージで並列に**起動する。各 agent は専門スキルを 1 つだけ実行し、JSON で指摘を返す。

**全 agent 共通のスコープ制約**（プロンプトに必ず含める）:
- 対象は `<base_ref>...HEAD` の差分のみ。差分に含まれないファイルはレビューしない
- 指摘は必ず差分内のファイル:行にアンカーする。差分外の既存問題は報告しない
- 差分外に重大な問題を見つけた場合は `out_of_scope` 配列に入れる（修正対象にはせず、レポートに残すだけ）

```
Agent({
  description: "refine-git iter <iter+1> — code-review-git",
  subagent_type: "claude",
  prompt: """
PR #<n>（branch: <branch>）に対して /code-review-git を Skill ツールで起動して実行。
引数には比較先ブランチ <base_ref> を渡すこと。

スコープ: <base_ref>...HEAD の差分のみ。差分外のファイルはレビュー対象外。
出力先を聞かれたら「コンソール出力」を選び、Issue は作成しないこと。

得られた指摘を以下の severity で分類し、JSON 1行で最終メッセージとして返す:
- critical: バグ・セキュリティ問題・データ破壊・テスト失敗
- major: 設計の重大欠陥・パフォーマンス劣化・公開 API の不整合
- minor: 命名・コメント・微細な readability・スタイル

差分外に見つけた重大な問題は critical/major/minor には入れず out_of_scope に入れる。

{"source": "code-review-git", "critical": [{"file":"...", "line": N, "msg":"..."}], "major": [...], "minor": [...], "out_of_scope": [...]}
"""
})

Agent({
  description: "refine-git iter <iter+1> — doc-drift-git",
  ... 同様、/doc-drift-git を <base_ref> 付きで実行、 "source": "doc-drift-git" で返す
})

Agent({
  description: "refine-git iter <iter+1> — spec-audit-git",
  ... 同様、/spec-audit-git を `<base_ref> --report-only` 付きで実行、 "source": "spec-audit-git" で返す
  # --report-only により Issue 作成と対話がスキップされ、レポートのみ返る
})

# HAS_HALT=true のときのみ追加（変更ファイルのパスを引数で渡す）
Agent({
  description: "refine-git iter <iter+1> — halt-review",
  ... /halt-review <差分内の対象パス列> を実行、 "source": "halt-review" で返す
  # 引数のパス以外は走査させない。指摘も差分内に限定させる
})

# HAS_ATOMIC=true のときのみ追加（変更ファイルのパスを引数で渡す）
Agent({
  description: "refine-git iter <iter+1> — atomic-review",
  ... /atomic-review <差分内の対象パス列> を実行、 "source": "atomic-review" で返す
})
```

各 agent の返答 JSON を集約:

```bash
# 全 source の critical / major / minor を結合（out_of_scope は閾値判定に含めない）
findings=$(printf '%s\n' "$resp_code" "$resp_doc" "$resp_spec" "$resp_halt" "$resp_atomic" | \
  jq -s '{
    critical: map(.critical // []) | flatten,
    major:    map(.major // [])    | flatten,
    minor:    map(.minor // [])    | flatten,
    out_of_scope: map(.out_of_scope // []) | flatten,
    by_source: map({(.source): {c:(.critical|length), m:(.major|length), mn:(.minor|length)}}) | add
  }')

# 差分外アンカーの指摘を除外（review agent がスコープを守らなかった場合の保険）
findings=$(echo "$findings" | jq --argjson cf "$(printf '%s\n' "$changed_files" | jq -R -s 'split("\n") | map(select(length > 0))')" '
  def in_diff: select(.file == null or (.file as $f | $cf | index($f)));
  .critical |= map(in_diff) | .major |= map(in_diff) | .minor |= map(in_diff)')
```

`out_of_scope` は**閾値判定にも修正対象にも含めない**（フェーズ3 のレポートに記録するだけ）。

### 2-2. テレメトリ追記 + state.json 更新

`refine` の `references/state-and-telemetry.md` の「反復ごとのテレメトリ追記 + state.json 更新」を実行する（`source` は `refine-git` になる）。

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
  description: "refine-git iteration <iter+1> fix",
  subagent_type: "claude",
  prompt: """
PR #<n>（branch: <branch>）の以下の指摘を修正してください:

CRITICAL:
<critical 指摘の file:line:msg を列挙>

MAJOR:
<major 指摘を列挙>

MINOR (excess minor が <minor - max_minor> 件あるので優先度高いものを <minor - max_minor> 件以上修正):
<minor 指摘を列挙>

**スコープ制約（厳守）**:
- 変更してよいのは以下の差分内ファイルのみ:
  <changed_files を列挙>
- 上記以外のファイルは編集しない。指摘の修正に差分外ファイルの変更が不可欠な場合は、
  修正せず {"failure": "out_of_scope_required: <ファイル> <理由>"} を返して判断を委ねる
- ただし修正に伴うテストファイルの新規追加は許可する（回帰テストは必須）
- 差分外に別の問題を見つけても直さない。**Issue も作らない**（`/spinoff-issue` を呼ばない）。
  最終 JSON の spinoff に記録するだけにして次に進む。フェーズ3 のレポート
  `## Out of scope` に集約される

手順:
1. `git checkout <branch>` で切り替え
2. develop エージェント (Agent(develop)) で順番に修正
3. テストが必要なら追加
4. `git push` で修正コミットを push
5. 最終メッセージ JSON: {"fixed_critical": N, "fixed_major": N, "fixed_minor": N, "commit": "<sha>", "spinoff": ["<差分外で見つけた問題>"]}
   または失敗時: {"failure": "<理由>"}
"""
})
```

失敗時はループ中断し stuck 扱いでフェーズ3 へ。

### 2-5. 次の反復

修正 push により差分が広がっているため、`changed_files` を再取得してからフェーズ2-1 に戻る:

```bash
merge_base=$(git merge-base "$base_ref" HEAD)
changed_files=$(git diff --name-only "$merge_base"...HEAD)
```

`iter+=1` してフェーズ2-1 に戻る。

## フェーズ3: マージ → レポート生成と終了

`refine` の `references/merge-and-report.md` の手順 1〜8 を実行する。

**本スキル固有の追加**: 手順 6 のレポート生成後、`## Out of scope` セクションを追記する:

```bash
cat >> "$report" <<EOF

## Out of scope（差分外で検出、未修正）

> refine-git は差分のみを修正対象とする。全体を磨くなら /refine または /refine-sweep を使う。

$(echo "$findings" | jq -r '.out_of_scope[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"' || echo "なし")
EOF
```

各反復の修正 agent が返した `spinoff` 配列も同じセクションに追記する（重複は除く）。この一覧が「Issue 化するか」をユーザーが判断する材料になるので、**空でない限り必ず出力する**。

## 禁止行動

- **メインスレッド自身がコードを修正する**（CTO は実装に触らない、impl-wt や issue-sweep と同じ原則）
- review agent と fix agent を同じ呼び出しで混ぜる（独立性を保つ）
- 閾値到達してないのに「もういいでしょう」とループを打ち切る
- `max_iter` を超えても無限ループする
- minor の修正で副作用バグを入れない（修正後の review で critical が出たら反復継続）
- **全体スキャン版のレビュースキル（`code-review` / `doc-drift` / `spec-audit`）を起動する**（必ず `-git` 版を使う。全体版が要るなら `/refine` か `/refine-sweep`）
- **`halt-review` / `atomic-review` を引数なしで起動する**（プロジェクト全体走査になる。必ず差分内の対象パスを引数で渡す）
- **差分外のファイルを修正する**（2-4 のスコープ制約を修正 agent のプロンプトから省略しない。差分外の問題は `out_of_scope` / `spinoff` に記録するだけ）
- **修正ループ内で `/spinoff-issue` を呼ぶ**（fix agent は `max_iter` 回起動されるので反復回数ぶん Issue が量産される。差分外の発見はレポートの `## Out of scope` に集約し、Issue 化するかはユーザーが判断する）
- **`out_of_scope` の指摘を閾値判定に含める**（差分外の既存問題で永久にループが収束しなくなる）
- **必須レビュー（code-review-git / doc-drift-git / spec-audit-git）の一部をスキップする**（全観点を統合して判定するため）
- **HALT プロジェクトで halt-review をスキップする**（HAS_HALT=true なら必ず並列起動）
- **Atomic Design プロジェクトで atomic-review をスキップする**（HAS_ATOMIC=true なら必ず並列起動。HAS_HALT=true との排他は検知側で担保）
- **フロントエンドプロジェクトで Atomic Design 未採用のまま続行する**（フェーズ1 の IS_FRONTEND ガードで必ず中断すること）
- **`.sweep/state.json` を `phase=terminal` にする前に最終 review を再実行せず、推定で `clean` を宣言する**
- **`.sweep/state.json` の `evidence` 配列が空のままフェーズ3 に進む / terminal 化する**
- レポートに `## Evidence` セクションを書かない
- **status=clean なのにマージをスキップする**（`--no-merge` 明示時を除く）
- **`gh pr merge --auto` を使う**（リポジトリ設定 `allow_auto_merge` の有無に挙動が依存し、OFF だと GraphQL エラーで止まる。CI 緑をポーリングしてから直接マージする方式に統一）
- マージ完了確認をスキップしてレポート生成に進む
- **メイン作業ツリーで checkout して PR ブランチに切り替える**（worktree 隔離を破ってメインを汚す原因）
