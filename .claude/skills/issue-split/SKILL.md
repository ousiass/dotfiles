---
name: issue-split
description: 指定したGitHub Issueを対話的にスコープ単位のサブissueに分割する
user-invocable: true
---

# issue-split

大きなIssue（spec-genで作成した仕様書Issue等）を、実装可能なスコープ単位のサブissueに分割する。
各サブissueの内容をユーザーと1つずつ確認しながら作成する。

## 前提条件

- Claude Code 環境
- `gh` CLI（認証済み）

## 引数

- **Issue 番号** (例: `/issue-split #123`): 分割対象のGitHub Issue
- **Issue URL** (例: `/issue-split https://github.com/owner/repo/issues/123`): 同上
- **引数なし**: ユーザーにIssue番号をヒアリング

## フェーズ1: Issue取得と分析

1. `gh issue view <番号> --json title,body,labels,url` で元Issueを取得
2. Issue本文にリンクされた仕様書があれば Read で読み込む
   - Glob で `**/spec/**/*.md`, `**/specs/**/*.md`, `**/docs/**/*.md` も探索
3. 要件の全体像を把握し、TaskCreate で「Issue分割」タスクを作成

## フェーズ2: スコープ分割の提案

1. Issueの内容を**独立して実装できるスコープ単位**に分割する
   - 典型的な分割軸: 環境構築、バックエンド（API/DB）、フロントエンド、テスト/CI等
   - 依存関係を考慮し実装順を決定
2. `AskUserQuestion` の `preview` に分割一覧を表示して確認する

   preview に載せるフォーマット:
   ```
   1. <タイトル>  [依存: なし]
      概要: ...
   2. <タイトル>  [依存: #1]
      概要: ...
   ```

3. 選択肢:
   - **この分割でOK** — そのまま進む
   - **もっと細かく分けたい** — 指定スコープをさらに分割
   - **もっとまとめたい** — スコープを統合
   - **分割を修正したい** — 自由記述で調整

4. ユーザーが納得するまで繰り返す

## フェーズ3: 各サブissueの対話的確認

**スコープごとに以下を繰り返す（実装順に1つずつ）:**

#### 3-1: サブissue下書き作成

元Issueと仕様書から該当スコープの情報を抽出し、下書きを作成する:

- **タイトル**: `<type>: <スコープの実装内容>` （implスキルがそのまま使えるタイトル）
  - type はスコープの性質で選択: `feat`（機能）, `chore`（環境構築）, `test`（テスト/CI）, `docs`（ドキュメント）等
- **本文**: `templates/sub-issue.md` のフォーマットに従う
- **ラベル**: 元Issueのラベルを引き継ぎ + スコープ別ラベル（例: `scope:backend`, `scope:frontend`）があれば付与

#### 3-2: ユーザー確認

`AskUserQuestion` で下書きをプレビュー表示し確認:

- **このまま作成する**
- **修正してから作成する** — 修正点を記述 → 反映 → 再確認
- **このスコープはスキップする**

## フェーズ4: サブissue作成とリンク

1. 承認済みの各サブissueを `gh issue create` で作成
   - ラベル指定: `--label <label1> --label <label2>`
   - 作成したissue番号を記録

2. 親Issueの本文末尾にサブissue一覧を追記する:
   1. `gh issue view <番号> --json body -q .body` で既存本文を取得
   2. 末尾に「## サブissue」セクションを追加（既にあれば既存リンクを残して追記）
      ```
      ## サブissue

      実装順に記載:
      - [ ] #<番号> <タイトル>
      - [ ] #<番号> <タイトル>
      ```
   3. 一時ファイルに書き出し `gh issue edit <番号> --body-file <一時ファイル>` で更新
   4. 一時ファイルを削除

3. 作成結果のサマリーをユーザーに報告:
   - 親Issue URL
   - 各サブissue URL と実装順
   - `impl` スキルでの実行例: `/impl #<最初のサブissue番号>`

## ルール

- 質問には必ず `AskUserQuestion` を使い選択式で提示する。テキストだけで質問しない
- 1回あたり4問以内にまとめる
- 各選択肢の `description` に判断材料を記載する
- サブissueのタイトルは `impl` スキルが読んで実装に取り組める形式にする
- Issue作成前に必ずユーザーの承認を得る
- 元Issueの内容を改変しない（サブissueセクションの追記のみ）
- TaskCreate/TaskUpdate で進捗を管理する
