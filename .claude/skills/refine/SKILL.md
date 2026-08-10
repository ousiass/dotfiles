---
name: refine
description: リポジトリ全体を対象に review→修正→再review を反復し研磨後、CI 緑を待って直接マージし Issue close まで実行する。
user-invocable: true
---

# refine

review → 修正 → 再 review を回し、**リポジトリ全体**をレビュー観点で「軽微指摘のみ」状態まで持っていくスキル。修正は 1 本の PR ブランチ上に直接積む。

**PR の差分だけを磨きたい場合は `refine-git` を使うこと。** `impl` / `impl-wt` / `issue-sweep` が作った PR の研磨はすべて `refine-git` の担当。本スキルを機能 PR に対して使うとスコープが膨張し、閾値に到達しないまま `max_iter` で打ち切られる。

| スキル | 対象 | 修正の流し方 | 主な用途 |
|---|---|---|---|
| `refine-git` | PR の差分のみ | PR ブランチ上で直接修正 | 機能 PR の研磨（既定） |
| **refine**（本スキル） | リポジトリ全体 | PR ブランチ上で直接修正（1 PR にまとめる） | 小〜中規模リポジトリの一括クリーンアップ |
| `refine-sweep` | リポジトリ全体 | Issue 化 → `impl-wt` で消化（複数 PR） | 大規模リポジトリの継続的な品質改善 |

## 引数

- `/refine` — 現在のブランチ / PR を対象
- `/refine #<PR番号>` — 特定 PR を対象
- `/refine --max-minor <N>` — minor 指摘の上限（デフォルト 5）
- `/refine --max-iter <N>` — レビューループ反復上限（デフォルト 10）
- `/refine --no-merge` — 研磨のみでマージしない（デフォルトは CI 緑を待って直接マージまで実行）

## 前提

- `git`, `gh` CLI 認証済み
- 対象 PR / ブランチが checkout 可能
- `.sweep/` ディレクトリへの書き込み権限（テレメトリ用）

## フェーズ1: セットアップとレビュー対象スキル決定

`skill_name="refine"` / `scope_label="リポジトリ全体"` を設定し、`references/common-setup.md` の手順 1〜7 を実行する（ターゲット特定・worktree 確保・変数初期化・state.json 初期化・HALT / Atomic Design 検知・フロントエンドガード）。

状態管理の仕様は `references/state-and-telemetry.md` を参照。

### 1-8. レビュー対象スキル一覧の決定（すべて全体スキャン版）

- 常に: `code-review`, `doc-drift`, `spec-audit`
- `HAS_HALT=true` のみ: `halt-review` を追加
- `HAS_ATOMIC=true` のみ: `atomic-review` を追加

## フェーズ2: review → 修正ループ

各反復で `Agent(subagent_type=claude)` を**レビュースキルごとに並列起動**。**メインスレッドはコードに触れない**。

### 2-1. レビュー集約（並列）

決定したスキル群を**同一メッセージで並列に**起動する。各 agent は専門スキルを 1 つだけ実行し、JSON で指摘を返す。

```
Agent({
  description: "refine iter <iter+1> — code-review",
  subagent_type: "claude",
  prompt: """
リポジトリ全体に対して /code-review を Skill ツールで起動して実行。
出力先を聞かれたら「コンソール出力」を選び、Issue は作成しないこと。

得られた指摘を以下の severity で分類し、JSON 1行で最終メッセージとして返す:
- critical: バグ・セキュリティ問題・データ破壊・テスト失敗
- major: 設計の重大欠陥・パフォーマンス劣化・公開 API の不整合
- minor: 命名・コメント・微細な readability・スタイル

{"source": "code-review", "critical": [{"file":"...", "line": N, "msg":"..."}], "major": [...], "minor": [...]}
"""
})

Agent({
  description: "refine iter <iter+1> — doc-drift",
  ... 同様、/doc-drift を実行、 "source": "doc-drift" で返す
})

Agent({
  description: "refine iter <iter+1> — spec-audit",
  ... 同様、/spec-audit を実行、 "source": "spec-audit" で返す
  # spec-audit は通常 Issue を作成するスキル。refine からの呼び出し時は
  # 「Issue は作らず指摘 JSON のみ返してください」とプロンプトで明示すること
})

# HAS_HALT=true のときのみ追加
Agent({
  description: "refine iter <iter+1> — halt-review",
  ... 同様、/halt-review を実行、 "source": "halt-review" で返す
})

# HAS_ATOMIC=true のときのみ追加
Agent({
  description: "refine iter <iter+1> — atomic-review",
  ... 同様、/atomic-review を実行、 "source": "atomic-review" で返す
})
```

各 agent の返答 JSON を集約:

```bash
findings=$(printf '%s\n' "$resp_code" "$resp_doc" "$resp_spec" "$resp_halt" "$resp_atomic" | \
  jq -s '{
    critical: map(.critical // []) | flatten,
    major:    map(.major // [])    | flatten,
    minor:    map(.minor // [])    | flatten,
    by_source: map({(.source): {c:(.critical|length), m:(.major|length), mn:(.minor|length)}}) | add
  }')
```

### 2-2. テレメトリ追記 + state.json 更新

`references/state-and-telemetry.md` の「反復ごとのテレメトリ追記 + state.json 更新」を実行する（`source` は `refine` になる）。

### 2-3. 閾値判定

```
if critical == 0 && major == 0 && minor <= max_minor:
  → success, フェーズ3 へ
if iter >= max_iter:
  → stuck, フェーズ3 へ（残指摘ありで終了）
otherwise:
  → 2-4 へ
```

**打ち切りの目安**: 全体スキャンは初回の指摘件数が大きくなりやすい。1 PR に収まらない規模（critical + major が 30 件超など）と判明した時点で、`refine-sweep` への切り替えをユーザーに提案してよい。

### 2-4. 修正 agent

```
Agent({
  description: "refine iteration <iter+1> fix",
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
3. テストが必要なら追加（リグレッションテストは必須）
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

`references/merge-and-report.md` の手順 1〜8 を実行する。

## 禁止行動

- **メインスレッド自身がコードを修正する**（CTO は実装に触らない、impl-wt や issue-sweep と同じ原則）
- review agent と fix agent を同じ呼び出しで混ぜる（独立性を保つ）
- 閾値到達してないのに「もういいでしょう」とループを打ち切る
- `max_iter` を超えても無限ループする
- minor の修正で副作用バグを入れない（修正後の review で critical が出たら反復継続）
- **機能 PR に対して本スキルを使う**（差分外の既存問題まで拾ってスコープが膨張する。`refine-git` を使うこと）
- **必須レビュー（code-review / doc-drift / spec-audit）の一部をスキップする**（全観点を統合して判定するため）
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
