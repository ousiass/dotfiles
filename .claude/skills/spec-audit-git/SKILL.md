---
name: spec-audit-git
description: gitリモートとの差分を対象に仕様と実装の乖離・TODO・スキップテストを検知しIssue化する。
user-invocable: true
---

# spec-audit-git

`spec-audit` の差分版。**変更差分に起因する**仕様乖離・未実装・TODO・スキップテストのみを検知する。
PR 作成前のセルフ監査や `refine-git` からの呼び出しに最適。

## 前提条件

- Claude Code 環境
- `git`, `gh` CLI

## 引数

- 引数なし: 現在のブランチと `origin/develop` との差分を対象
- ブランチ指定: 比較先のリモートブランチを指定（例: `origin/main`）
- `--report-only`: Issue を作成せずレポート出力のみ（対話もスキップ。`refine-git` からの呼び出し用）

## スコープ規約

`doc-drift-git` の「差分 × 差分」とは異なり、**差分コードに関連する仕様書は差分外でも読む**（仕様書が更新されていないこと自体が検知対象のため）。ただし:

- **すべての指摘は差分内のファイル:行にアンカーする**
- 仕様書に書かれていても、差分と無関係な未実装は**報告しない**（それは `spec-audit` の仕事）
- TODO/FIXME・スキップテストは**差分で追加された行のみ**（既存の残存マーカーは対象外）

## フェーズ1: 差分の取得と分類

1. `git fetch origin`
2. 比較元ブランチを決定（引数あり → 引数使用 / なし → `origin/develop`）
3. マージベースを取得（`git merge-base <比較元> HEAD`）
4. 差分ファイル一覧（`git diff --name-status <merge-base>...HEAD`）
5. コミット一覧（`git log --oneline <merge-base>..HEAD`）
6. 差分ファイルを分類:
   - **仕様書**: `docs/`, `spec/`, `README.md`, `ARCHITECTURE.md`, OpenAPI/Swagger 定義
   - **実装**: ソースコード、設定、マイグレーション
   - **テスト**: テストファイル
7. TaskCreate でチェック対象をタスク化

## フェーズ2: 関連仕様書の特定

差分の実装ファイルから、関連する仕様書を特定する（差分外も可）。

1. 変更されたエンドポイント・関数・設定項目・データモデルを差分から抽出
2. 抽出した名前を `Grep` で仕様書群から検索し、記述箇所を特定
3. 関連仕様書が 1 件も見つからない場合はフェーズ3-1 をスキップ（乖離判定材料がない）

## フェーズ3: 突き合わせ

検知観点は `references/check-criteria.md` を参照。

#### 3-1: 差分コード vs 仕様書

| パターン | 状態 | 重大度の目安 |
|---------|------|------------|
| 仕様書の記述と差分の実装が矛盾 | 不一致 | 🔴〜🟠 |
| 仕様書の変更あり・対応する実装が差分にない | 未実装 | 🔴〜🟠 |
| 差分で API/設定/データモデルを変更・仕様書が未追随 | 更新漏れ | 🟠〜🟡 |

#### 3-2: 差分で追加された TODO/FIXME

```bash
git diff <merge-base>...HEAD -U0 | grep -nE '^\+.*\b(TODO|FIXME|HACK|XXX|TEMP|WORKAROUND)\b'
```

差分で**追加**された行のみを対象とする。既存行は対象外。

#### 3-3: 差分で追加・変更されたスキップテスト

同様に差分の追加行から skip/pending/xit 等を検出（パターンは `references/check-criteria.md`）。
既存テストが差分で skip 化された場合は 🟠 以上とする。

#### 3-4: API スキーマ乖離（差分に定義変更がある場合のみ）

OpenAPI/Swagger 定義が差分に含まれる場合、追加・変更されたエンドポイントに対応するハンドラが実装差分にあるか確認する。

## フェーズ4: レポート生成

1. 検出結果を重大度別に集計（基準は `references/check-criteria.md`）
2. `templates/report.md` の形式でレポートを生成
3. `--report-only` 指定時: レポートをそのまま会話に出力してここで終了（フェーズ5 はスキップ）
4. 未指定時: `AskUserQuestion` で出力先を確認
   - **GitHub Issue に作成**（推奨）
   - **ローカル MD ファイル**: `spec-audit-git-report.md`
   - **コンソール出力**

## フェーズ5: Issue 作成

出力先で「GitHub Issue に作成」が選ばれた場合のみ実行する。

1. 全件の一覧（タイトル + 重大度）を表示
2. `AskUserQuestion` で作成方式を確認（まとめて1つ / 個別）
3. 重複チェック: `gh issue list --state open --search "<要約>"`
4. Issue 本文は `templates/issue.md` を参照
5. `gh issue create` で作成。ラベル: `spec-audit` + 重大度ラベル（`severity:critical` 等）
6. 作成した Issue の URL を報告

## ルール

- **差分に集中。** 差分と無関係な未実装・TODO・スキップテストは報告しない
- 推測で乖離を報告しない。**実装コードと差分で裏付けを取る**
- 乖離には仕様書側と実装側の**両方の箇所**を示す（実装側は差分内であること）
- コードを修正しない。成果物は Issue とレポートのみ
- Issue 作成前に必ず承認を得る（`--report-only` 時は Issue を作らない）
- 検知粒度は機能・エンドポイント単位（「DELETE /users/:id が未実装」のように具体的に）
- TaskCreate/TaskUpdate で進捗を管理する
