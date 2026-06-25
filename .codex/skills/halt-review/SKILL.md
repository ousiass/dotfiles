---
name: halt-review
description: HALTアーキテクチャ準拠レビューを行う（ルーティング整合性、Templ/HTMX 接続、Atomic Design、Lit 使用基準、Go レイヤー、セキュリティ、ビルド設定）。ユーザーが HALT 採用プロジェクトのアーキテクチャ準拠チェック、コードレビュー、構造監査を依頼したときに使う。
---

# halt-review

HALTアーキテクチャ（HTMX + Atomic Design + Lit + Templ + Huma）で構築されたプロジェクトを、HALT固有の観点でレビューする。

## 前提条件

- Codex CLI 環境
- `gh` CLI（GitHub Issue 出力時）
- 対象プロジェクトがHALTアーキテクチャを採用していること

## 引数

- 引数なし: カレントディレクトリのプロジェクト全体をチェック
- パス指定: 指定したディレクトリまたはファイルのみチェック

## Phase 1: プロジェクト構造の把握

1. ディレクトリ構成を確認し、HALTの各レイヤーを特定する
   - Goソース（`internal/`, `cmd/`）
   - Templテンプレート（`web/` 配下の `atoms/`, `molecules/`, `organisms/`, `pages/`, `layout/`）
   - Litコンポーネント（`static/src/components/` または類似パス）
   - ルーティング定義（`router/` または `handler/`）
   - ビルド設定（`esbuild.config.*`, `package.json`）
2. アプリプレフィックスを検出する（Web Componentsの `@customElement` 定義から推定）
3. 対象ファイル一覧を作成し、チェック項目ごとに進捗を管理する

## Phase 2: HALTレビュー

全チェック観点を順に実行する。**対象ファイルはすべてチェックする。** ファイル数が多い場合はディレクトリ単位で分割して処理する。

チェック観点の詳細:
- ルーティング整合性: `references/check-routing.md`
- Templ ↔ HTMX 接続: `references/check-templ-htmx.md`
- クロスレイヤー整合性: `references/check-cross-layer.md`
- HATEOAS 準拠: `references/check-hateoas.md`
- Atomic Design 構造: `references/check-atomic.md`
- Lit Web Components: `references/check-lit.md`
- Go レイヤードアーキテクチャ: `references/check-backend-layer.md`
- セキュリティ: `references/check-security.md`
- ビルド・設定: `references/check-build.md`

## Phase 3: レポート生成

1. 選択式でユーザーに出力先を確認する（自由入力を許容）:
   - **GitHub Issue**（推奨）: タイトル `halt-review: HALTアーキテクチャレビュー (<branch>, <YYYY-MM-DD>)`
   - **ローカルMDファイル**: `halt-review-report.md`
   - **コンソール出力**: 会話に直接レポート表示
2. `templates/report.md` のフォーマットを使用
3. サマリーをユーザーに報告

## 重大度基準

| 重大度 | 基準 |
|--------|------|
| Critical | ルーティング不整合（存在しないパスへのHTMXリクエスト）、Templ↔Lit属性バインディング不一致、静的アセットパス不一致、セキュリティ欠陥（CSRF未適用） |
| Important | HATEOAS違反（hidden/disabledでアクション制御、Lit URL ハードコード）、HALT設計思想の違反（HTMLを返すべき箇所でJSON返却、不要なWeb Component使用）、Atomic Design/Goレイヤーの依存方向逆転、Huma登録漏れ・I/O構造体欠如、Templ生成ファイルの鮮度 |
| Suggestion | 命名規則の不統一、コンポーネント配置の最適化、hx-swap戦略の改善 |
| Minor | コード整理、スタイル統一、軽微な命名改善 |

## ルール

- 推測で指摘しない。実際のコードを検証して報告する
- 指摘には必ずファイルパスと行番号を含める
- 具体的な改善案を提示する
- Critical / Important は必ず含める。Suggestion / Minor は明確なメリットがある場合のみ
- プロジェクト固有の慣習や既存コードスタイルを尊重する
- 計画立てしつつ進捗を管理する
