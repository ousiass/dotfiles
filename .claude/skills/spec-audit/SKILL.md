---
name: spec-audit
description: 仕様書と実装の乖離を全方位チェックし、未実装・TODO・スキップテスト等をIssue化する
user-invocable: true
---

# spec-audit

仕様書を正（Single Source of Truth）として、実装漏れ・乖離を検知し GitHub Issue を作成する。

## 前提条件

- Claude Code 環境
- `gh` CLI（Issue 作成時）

## 引数

- **引数なし**: 対話でヒアリングしてから全体チェック
- **パス指定** (例: `/spec-audit docs/api-spec.md`): 特定ドキュメントに絞ってチェック

## フェーズ1: ヒアリング

引数でパスが指定されていない場合、プロジェクトルートを `Glob` で自動探索する：
- `docs/`, `spec/` 配下
- `README.md`, `ARCHITECTURE.md`, `CLAUDE.md`
- OpenAPI/Swagger 定義 (`*.yaml`, `*.json`)
- その他 `.md` ファイル

検出したドキュメント一覧をユーザーに示し、チェック対象を確認する。

**検知粒度は機能・エンドポイント単位**。セクション丸ごとではなく「DELETE /users/:id が未実装」のように具体的な単位で報告する。

検知対象は以下のすべて：
1. **仕様 vs 実装**: 仕様書に定義されているが未実装の機能
2. **TODO/FIXME/HACK**: コード内の未完了マーカー
3. **スキップテスト**: `skip`, `pending`, `xit`, `xdescribe` 等
4. **APIスキーマ乖離**: OpenAPI/Swagger 定義 vs 実装ハンドラ

## フェーズ2: ドキュメント探索

1. Q1 で決まった対象のドキュメントを読み取る
2. 各ドキュメントから具体的な主張・仕様を抽出する：
   - エンドポイント定義、関数シグネチャ、CLI 引数
   - データモデル、テーブル定義
   - 機能一覧、振る舞いの記述
   - 設定項目、環境変数
3. `TaskCreate` でチェック対象をタスク化する

## フェーズ3: 実装との突き合わせ

検知観点は `references/check-criteria.md` を参照。

#### 3-1: 仕様 vs 実装

1. ドキュメント内の主張（関数名、パス、設定値、振る舞い等）を1つずつ抽出
2. `Explore` エージェントや `Grep`/`Glob` で対応する実装を探す
3. 一致・不一致・未実装を判定
4. 不一致はドキュメント側の行と実装側のファイル:行を記録

#### 3-2: TODO/FIXME/HACK

1. `Grep` で `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP` を検索
2. 各マーカーの内容・ファイル・行番号を記録
3. 仕様書との関連があれば紐付ける

#### 3-3: スキップテスト

1. `Grep` で以下を検索：
   - JS/TS: `it.skip`, `describe.skip`, `xit`, `xdescribe`, `test.skip`
   - Go: `t.Skip`
   - Python: `@pytest.mark.skip`, `@unittest.skip`, `self.skipTest`
   - Ruby: `skip`, `pending`
   - その他: プロジェクトの言語に応じて調整
2. 各スキップの理由コメント・ファイル・行番号を記録

#### 3-4: API スキーマ乖離

1. OpenAPI/Swagger 定義があれば読み取る
2. 定義済みエンドポイントに対応するハンドラ・ルートを検索
3. 未実装エンドポイントを記録

## フェーズ4: レポート生成と出力先の確認

1. 検出結果を重大度別に集計する（重大度基準は `references/check-criteria.md`）
2. `templates/report.md` の形式でレポートを生成
3. `AskUserQuestion` で出力先をユーザーに確認する：
   - **GitHub Issue に作成**（推奨）
   - **ローカル MD ファイルに保存**: プロジェクトルートに `spec-audit-report.md` を生成
   - **コンソール出力**: レポートをそのまま会話に出力

## フェーズ5: Issue 作成

出力先で「GitHub Issue に作成」が選ばれた場合：

1. 全件の一覧（タイトル + 重大度）をまとめて表示する
2. `AskUserQuestion` で Issue の作成方式を確認：
   - **まとめて1つの Issue**: 全検出結果をチェックリスト形式で1つの Issue にまとめる（推奨）
   - **個別 Issue**: 検出結果1件につき1 Issue を作成する
3. 重複チェック: `gh issue list --state open --search "<要約>"` で既存 Issue を検索。重複あり → スキップ or 新規作成か確認
4. Issue 本文は `templates/issue.md` を参照
5. `gh issue create` で作成。ラベル: `spec-audit` + 重大度ラベル（`severity:critical`, `severity:high`, `severity:medium`, `severity:low`）
6. 作成した Issue の URL をユーザーに報告

## ルール

- 推測で乖離を報告しない。**実装コードを確認して裏付けを取る**
- 乖離にはドキュメント側と実装側の**両方の箇所**を示す
- コードを修正しない。成果物は Issue とレポートのみ
- Issue 作成前に**必ず承認を得る**
- `TaskCreate`/`TaskUpdate` で進捗を管理する
- 検出件数が多い場合は重大度 🔴🟠 を優先し、🟡🟢 は省略可とする
