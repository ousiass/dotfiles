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
- `/refine-git --skip-minor` — minor 指摘を閾値判定と修正対象から外す（検出とレポートは行う）。`issue-sweep` からの呼び出しは常にこれを付ける
- `/refine-git --max-iter <N>` — レビューループ反復上限（デフォルト 10）
- `/refine-git --no-merge` — 研磨のみでマージしない（デフォルトは CI 緑を待って直接マージまで実行）
- `/refine-git --base-ref <ref>` — 差分の比較先を明示指定する（例: `origin/sweep/issue-sweep-20260831-120000`）。PR の baseRefName より優先する。**sweep の single-pr モードからの呼び出しは常にこれを付ける** — 統合ブランチではなく `origin/develop` と比較すると、既に統合済みの他バッチの差分までレビュー対象に入ってスコープが際限なく膨らむ

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
# 比較先の優先順: --base-ref > PR の baseRefName > origin/develop > origin/main
git fetch origin
if [[ -n "${base_ref_opt:-}" ]]; then
  # 明示指定は fallback しない（存在しないまま origin/main に落ちると差分が膨らむ）
  base_ref="$base_ref_opt"
  git rev-parse --verify "$base_ref" >/dev/null 2>&1 \
    || { echo "ERROR: --base-ref $base_ref が存在しません"; exit 2; }
else
  base_ref="origin/${base_branch:-develop}"
  git rev-parse --verify "$base_ref" >/dev/null 2>&1 || base_ref="origin/main"
fi

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

**候補（`source` 名）:**

- 常に候補: `code-review-git`, `doc-drift-git`, `spec-audit-git`
- `HAS_HALT=true` のみ候補に追加: `halt-review`（**変更ファイルのパスを引数で渡す**）
- `HAS_ATOMIC=true` のみ候補に追加: `atomic-review`（**変更ファイルのパスを引数で渡す**）

**毎反復で全候補を起動するのではない。** 反復ごとの起動対象は次のルールで決める:

| 反復 | 起動する source |
|---|---|
| `iter = 0` | **全候補** |
| `iter ≥ 1` | 「前回反復で critical または major を 1 件以上出した source」∪「`doc_dirty=true` なら `doc-drift-git` / `spec-audit-git`」 |

`doc_dirty` は「直前の修正が `docs/` 配下または `*.md` を触ったか」（2-5 で更新。`iter=0` は必ず `true`）。ドキュメント乖離はコードだけ直しても変化しないので、docs を触っていない反復で再スキャンするのは無駄。逆に docs を編集した反復では、その編集自体が新たな乖離を生むので再走させる。

**起動しなかった source の指摘は、前回反復の結果をそのまま持ち越して閾値判定に混ぜる**（起動しなかったことを「解決した」と扱ってはならない）。

このルールにより、**指摘ゼロだった観点は 2 周目以降走らない**（`code-review-git` が 1 周目でクリーンなら実質初回のみ）。トレードオフとして、その観点が拾うはずだった「修正の副作用」を見逃す可能性は残る（CI が最後の砦）。

`halt-review` / `atomic-review` には差分版が存在しないため、`changed_files` のうち各スキルの対象拡張子（`.templ` / `.go` / `.ts` / `.tsx` / `.vue` 等）に該当するパスだけを引数として渡し、走査範囲を差分に限定する。該当パスが 0 件ならそのスキルは起動しない。

## フェーズ2: review → 修正ループ

各反復で `Agent(subagent_type=claude)` を**レビュースキルごとに並列起動**。**メインスレッドはコードに触れない**。

### 2-1. レビュー集約（並列）

決定したスキル群を**同一メッセージで並列に**起動する。各 agent は専門スキルを 1 つだけ実行し、JSON で指摘を返す。

**全 agent 共通のスコープ制約**（プロンプトに必ず含める）:
- 対象は `<base_ref>...HEAD` の差分のみ。差分に含まれないファイルはレビューしない
- 指摘は必ず差分内のファイル:行にアンカーする。差分外の既存問題は報告しない
- 差分外に重大な問題を見つけた場合は `out_of_scope` 配列に入れる（修正対象にはせず、レポートに残すだけ）
- 差分内の指摘であっても、**修正に差分外の非ドキュメントファイル**（実装コード・型定義・CI / 設定ファイル）の変更が不可欠なものは severity ではなく `out_of_scope` に入れる（fix agent が構造的に直せないため）。**ドキュメント / 仕様書の更新漏れはこれに該当しない** — 2-4 で差分外でも編集を許可しているので通常の指摘として扱う

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

# 1-9 の起動ルールに合致する source だけ起動する（iter>=1 は前回 critical/major を出した source ＋ doc_dirty）
Agent({
  description: "refine-git iter <iter+1> — doc-drift-git",
  ... 同様、/doc-drift-git を <base_ref> 付きで実行、 "source": "doc-drift-git" で返す
})

Agent({
  description: "refine-git iter <iter+1> — spec-audit-git",
  ... 同様、/spec-audit-git を `<base_ref> --report-only` 付きで実行、 "source": "spec-audit-git" で返す
  # --report-only により Issue 作成と対話がスキップされ、レポートのみ返る
})

# HAS_HALT=true ∧ 起動ルール合致のときのみ（変更ファイルのパスを引数で渡す）
Agent({
  description: "refine-git iter <iter+1> — halt-review",
  ... /halt-review <差分内の対象パス列> を実行、 "source": "halt-review" で返す
  # 引数のパス以外は走査させない。指摘も差分内に限定させる
})

# HAS_ATOMIC=true ∧ 起動ルール合致のときのみ（変更ファイルのパスを引数で渡す）
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

**1-9 の起動ルールで起動しなかった source の分は、前回反復の返答をそのまま再利用して集約に混ぜる。** 起動しなかった source を空扱いにすると未解決の指摘が消えて誤って閾値に到達する。

### 2-2. テレメトリ追記 + state.json 更新

`refine` の `references/state-and-telemetry.md` の「反復ごとのテレメトリ追記 + state.json 更新」を実行する（`source` は `refine-git` になる）。

### 2-3. 閾値判定

```
if critical == 0 && major == 0 && (skip_minor || minor <= max_minor):
  → status=clean, フェーズ3 へ
if iter >= max_iter:
  → status=iter_limit, フェーズ3 へ（残指摘ありで終了）
if 2 反復連続で (critical + major) が前回以下に減っていない:
  → status=no_progress, フェーズ3 へ
otherwise:
  → 2-4 へ
```

**status は `merge-and-report.md` の enum（`clean` / `iter_limit` / `no_progress` / `agent_failed` / `merge_failed` / `ci_gave_up`）から選ぶ。`stuck` のような enum 外の文字列を作らない**（呼び出し元の `issue-sweep` が parse する）。

`--skip-minor` 指定時（`issue-sweep` からの呼び出しは常にこれ）は minor を閾値判定にも 2-4 の修正対象にも含めない。minor は命名・コメント・readability なので直すたびに差分が広がって新しい minor が生え、`max_iter` まで反復が回り続ける。呼び出し元のマージゲートが minor を見ていないなら、その反復は丸ごと無駄。

**no_progress の判定**: state.json の `last_counts` に前回の値が入っている。今回の `critical + major` が前回と同じかそれ以上なら「停滞」を 1 つ数え、**2 回連続で停滞したら打ち切る**（1 回で切らないのは、修正の副作用で一時的に増えることがあるため）。減っていれば停滞カウントを 0 に戻す。

同じ指摘を何周も回し続けるのが `max_iter` までの時間の大半を占めるので、直せない指摘は早めに人に返す。フェーズ3 のレポートには `status: no_progress` と、停滞した時点の残指摘を必ず載せる。

### 2-4. 修正 agent

agent を起動する**前に**メインスレッドで `prev_head=$(git rev-parse HEAD)` を控える（2-5 で「今回の修正で触ったファイル」を出すのに使う）。

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
（`--skip-minor` 指定時はこの MINOR ブロックを渡さない）

**スコープ制約（厳守）**:
- 変更してよいのは以下の差分内ファイルのみ:
  <changed_files を列挙>
- **例外1（ドキュメント）**: `docs/**`、リポジトリ直下の `*.md`、仕様書ディレクトリ配下のファイルは
  **差分外でも編集を許可する**。doc-drift-git / spec-audit-git の指摘は本質的に
  「コードは変わったのにドキュメントが追随していない」なので、差分外の docs を触れないと
  原理的に修正不能になる。ドキュメント更新はその PR の責務として扱う
- **例外2（テスト）**: 修正に伴うテストファイルの新規追加は許可する（回帰テストは必須）
- 上記以外の差分外ファイル（実装コード・型定義・CI / 設定ファイル）の変更が不可欠な場合は、
  修正せず {"failure": "out_of_scope_required: <ファイル> <理由>"} を返して判断を委ねる
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

失敗時はループ中断し `status=agent_failed` でフェーズ3 へ。

### 2-5. 次の反復

修正 push により差分が広がっているため、`changed_files` を再取得する:

```bash
prev_head=$(git rev-parse HEAD)   # ← 2-4 の修正 push の *前* に控えておいた値
merge_base=$(git merge-base "$base_ref" HEAD)
changed_files=$(git diff --name-only "$merge_base"...HEAD)
```

**2 周目以降はレビュー範囲を絞る。** 1 周目で見た差分の大半は修正で変わっていないので、全差分を毎回スキャンし直すのは無駄:

```bash
# レビュー範囲 = 前回の修正で触ったファイル ∪ 未解決指摘があるファイル
touched=$(git diff --name-only "$prev_head"...HEAD)
unresolved=$(echo "$findings" | jq -r '(.critical + .major + .minor)[].file // empty')
review_scope=$(printf '%s\n%s\n' "$touched" "$unresolved" | sort -u | grep -v '^$')
```

**次反復の起動対象を確定する**（1-9 のルール）:

```bash
# 直前の修正が docs を触ったか
if echo "$touched" | grep -qE '^(docs/|.*\.md$)'; then doc_dirty=true; else doc_dirty=false; fi

# 今回 critical/major を出した source（次反復で再走する対象）
active_sources=$(echo "$findings" | jq -r '.by_source | to_entries[] | select(.value.c > 0 or .value.m > 0) | .key')
```

次の反復では `changed_files` ではなく `review_scope` を各レビュー agent に渡す（差分外アンカーの除外 2-1 は `changed_files` のままでよい。スコープ判定と閲覧範囲は別）。`review_scope` が空になることはない（空なら閾値を満たしているはずなので 2-3 で success になっている）。

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
- 閾値到達してないのに「もういいでしょう」とループを打ち切る（打ち切ってよいのは `max_iter` 到達と 2-3 の no_progress 判定のときだけ）
- `max_iter` を超えても無限ループする
- **停滞（2 反復連続で critical+major が減らない）を無視して `max_iter` まで回し続ける**（直せない指摘を何周も回すのが所要時間の大半を占める。早めに人に返す）
- **2 周目以降も全差分をスキャンし直す**（2-5 の `review_scope` に絞る。変わっていないファイルを毎回読み直さない）
- minor の修正で副作用バグを入れない（修正後の review で critical が出たら反復継続）
- **全体スキャン版のレビュースキル（`code-review` / `doc-drift` / `spec-audit`）を起動する**（必ず `-git` 版を使う。全体版が要るなら `/refine` か `/refine-sweep`）
- **`halt-review` / `atomic-review` を引数なしで起動する**（プロジェクト全体走査になる。必ず差分内の対象パスを引数で渡す）
- **差分外のファイルを修正する**（2-4 のスコープ制約を修正 agent のプロンプトから省略しない。差分外の問題は `out_of_scope` / `spinoff` に記録するだけ）。ただし **2-4 の例外1（`docs/**` / `*.md` / 仕様書）と例外2（テスト追加）は差分外でも編集可**
- **doc-drift-git / spec-audit-git の指摘を「差分外のファイルが要るから」と修正せず捨てる**（ドキュメントは 2-4 の例外1 で編集可。`out_of_scope` に落としてよいのは実装コード・型定義・設定ファイルの差分外変更が必要なケースだけ）
- **`--skip-minor` 指定時に minor を閾値判定または修正対象に含める**（`issue-sweep` のマージゲートは minor を見ていないので、その反復は丸ごと無駄になる）
- **1-9 の起動ルールで起動しなかった source の前回指摘を持ち越さず、解決したものとして閾値判定する**（未解決の指摘を抱えたまま `clean` を宣言することになる）
- **2 周目以降も全候補 source を起動する**（1-9 の表に従う。前回クリーンだった観点を毎反復走らせるのが所要時間の大きな部分を占める）
- **`stuck` など `merge-and-report.md` の enum に無い status 名を作る**（呼び出し元が parse できない。`no_progress` を使う）
- **修正ループ内で `/spinoff-issue` を呼ぶ**（fix agent は `max_iter` 回起動されるので反復回数ぶん Issue が量産される。差分外の発見はレポートの `## Out of scope` に集約し、Issue 化するかはユーザーが判断する）
- **`out_of_scope` の指摘を閾値判定に含める**（差分外の既存問題で永久にループが収束しなくなる）
- **初回反復（`iter=0`）で候補 source の一部をスキップする**（1 周目は必ず全観点。絞れるのは 2 周目以降だけ）
- **HALT プロジェクトで halt-review をスキップする**（HAS_HALT=true なら必ず並列起動）
- **Atomic Design プロジェクトで atomic-review をスキップする**（HAS_ATOMIC=true なら必ず並列起動。HAS_HALT=true との排他は検知側で担保）
- **フロントエンドプロジェクトで Atomic Design 未採用のまま続行する**（フェーズ1 の IS_FRONTEND ガードで必ず中断すること）
- **最終反復のレビュー結果を確認せず、推定で `clean` を宣言する**（`--no-merge` 時は最終反復の結果をそのまま使う。確認のための re-review はしない）
- **呼び出し元 sweep が所有している `.sweep/state.json` を上書きする / `phase=terminal` にする**（`common-setup.md` 手順4 のガード参照。sweep のキュー処理を静かに終わらせる原因）
- **status=clean なのにマージをスキップする**（`--no-merge` 明示時を除く）
- **`gh pr merge --auto` を使う**（リポジトリ設定 `allow_auto_merge` の有無に挙動が依存し、OFF だと GraphQL エラーで止まる。CI 緑をポーリングしてから直接マージする方式に統一）
- マージ完了確認をスキップしてレポート生成に進む
- **メイン作業ツリーで checkout して PR ブランチに切り替える**（worktree 隔離を破ってメインを汚す原因）
