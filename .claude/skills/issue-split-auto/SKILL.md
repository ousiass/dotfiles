---
name: issue-split-auto
description: 大きな Issue を非対話的にスコープ単位のサブ Issue に分割する。issue-sweep からの呼び出し用。
user-invocable: true
---

# issue-split-auto

`/issue-split` の非対話型バリアント。`AskUserQuestion` を使わず、本文と仕様書を読んで自律的にサブ Issue を作成する。issue-sweep 等の自動フローから呼び出すことを想定。

対話的に調整したい場合は `/issue-split` を使う。

## 引数

- `/issue-split-auto #<n>` — Issue 番号
- `/issue-split-auto #<n> --max <N>` — 最大サブ Issue 数（デフォルト 8）
- `/issue-split-auto #<n> --dry-run` — 作成せず分割案を JSON で返すのみ

## 出力

最終メッセージは以下の JSON 1行のみ:

```json
{"parent": <親番号>, "children": [<子1>, <子2>, ...], "created": true|false}
```

`--dry-run` 時は `created: false` と `proposals: [{title, body, depends_on}, ...]` を返す。

## フェーズ1: 取得と分析

1. `gh issue view <n> --json number,title,body,labels,url`
2. 本文内のリンクや `**/spec/**`, `**/docs/**` から関連仕様書を Glob → Read
3. 本文構造を解析:
   - `## ` で始まる H2 セクション一覧
   - チェックボックス（`- [ ]`）のリスト一覧
   - 「バックエンド」「フロントエンド」「CI」「インフラ」「テスト」等のドメインキーワード

## フェーズ2: 分割案の生成（自律判断）

スコープ分割の優先順位（上から適用）:

1. **明示構造優先**: H2 セクションが3つ以上あればそれを単位にする
2. **チェックリスト優先**: トップレベルチェックボックスが5個以上あればグループ化（依存関係を本文から読む）
3. **ドメイン分割**: 典型分割軸 — 環境構築 / DB スキーマ / バックエンド API / フロントエンド / テスト / CI/CD
4. **フォールバック**: 上記いずれも該当しなければ分割せず空配列を返して終了

各サブ Issue 案は以下を持つ:
- **タイトル**: `[親Issueタイトルの短縮] - <スコープ名>`
- **本文**: 親 Issue へのリンク + そのスコープ部分の抜粋 + 受け入れ条件
- **依存**: 他サブ Issue への `Depends on #N`

`--max` を超える場合は近接スコープを統合して上限内に収める。

## フェーズ3: サブ Issue の作成

`--dry-run` でなければ:

```bash
for proposal in proposals:
  gh issue create \
    --title "<タイトル>" \
    --body "<本文>\n\n親: #<parent>" \
    --label "split-from:#<parent>"
  # 返ってきた Issue URL から番号を抽出して記録
```

ラベル `split-from:#<parent>` がリポジトリに存在しない場合は `gh label create` で先に作る（失敗してもラベル付与をスキップして続行）。

親 Issue にコメント追加:

```bash
gh issue comment <parent> --body "issue-split-auto によりサブ Issue に分割しました:
- #<child1>
- #<child2>
...
このトラッカー Issue は子がすべて close されたら手動で close してください。"
```

親 Issue 自体は close しない（トラッカーとして残す）。issue-sweep 側ではキュー上で親を子に置換する責務を持つ。

## 失敗時

- 分割対象でないと判断した場合: `{"parent": N, "children": [], "created": false, "reason": "splitting not warranted"}` を返す
- gh コマンド失敗: `{"failure": "<理由>", "parent": N}` を返す

## 分割しない判断基準

以下は分割せず親 Issue のままを返す:

- 本文 1500 文字未満かつ H2 セクション 3 未満
- バグ報告（label に `bug` 含む）
- すでに `split-from:#<n>` ラベルが付いた子 Issue
- 親 Issue がすでに他 Issue から split された（重複分割防止）
