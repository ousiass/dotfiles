---
name: halt
description: HALT（HTMX+Atomic+Lit+Templ）フロントエンドアーキテクチャを仕様書に追加する
user-invocable: true
---

# halt

## HALT とは

**H**TMX + **A**tomic Design + **L**it + **T**empl によるサーバー内蔵型フロントエンドアーキテクチャ。

- フロントエンドは API サーバー内で動作する（SPA を作らない）
- SSR + HTMX でハイパーメディア駆動のインタラクションを実現
- リッチUI が必要な箇所のみ Lit Web Components で拡張
- テンプレートは Atomic Design で構造化
- API サーバーはレイヤードアーキテクチャ（domain / repository / service / web）

詳細は `references/architecture.md` を参照。

## ワークフロー

### 1. 既存設計ドキュメントの探索

プロジェクト内の設計ドキュメントを自動探索する。

1. `docs/`, `spec/`, `specifications/`, `design/` ディレクトリを Glob で探索
2. `**/architecture*`, `**/frontend*`, `**/tech-stack*` 等のファイルも検索
3. 見つかったドキュメントを読み込み、現在のフロントエンドアーキテクチャ記述を把握

### 2. 差分の提示と方針決定

#### 既存の設計ドキュメントが見つかった場合

`references/architecture.md` と比較し、HALT アーキテクチャとの**差分一覧**を提示する。

差分の観点:
- 技術スタック（フレームワーク、テンプレートエンジン、スタイリング等）
- ディレクトリ構成（レイヤード構成、Atomic Design の有無）
- インタラクション方式（SPA vs HTMX vs その他）
- コンポーネント戦略（React/Vue vs Lit Web Components）
- ビルド構成

`AskUserQuestion` で確認:
- **HALT に変更する**: 差分箇所を HALT 仕様で上書き・追記
- **部分的に採用**: 変更する箇所を選択
- **キャンセル**: 変更しない

#### 既存の設計ドキュメントが見つからない場合

`AskUserQuestion` で確認:
- **新規作成する**: フロントエンドアーキテクチャ仕様書を作成
- **キャンセル**: 作成しない

新規作成先: `docs/architecture/frontend.md`（プロジェクトの慣習があればそれに従う）

### 3. プロジェクト情報のヒアリング

`AskUserQuestion` で以下を確認（1回にまとめる）:

- **アプリ名プレフィックス**: Web Components の命名に使用（例: `<myapp-doc-editor>`）
- **必要な Web Components**: リッチUI が必要な機能（エディタ、カンバン、チャート等）
- **追加の共通ライブラリ**: lib/ に含める機能（API クライアント、WebSocket、ロガー以外）
- **カスタマイズ**: HALT 標準構成から変更したい点があるか

### 4. 仕様書の生成

`references/architecture.md` をベースに、プロジェクト固有の情報を反映して仕様を生成する。

生成するセクション:

1. **フロントエンドアーキテクチャ概要** — HALT の設計思想と技術スタック表
2. **ディレクトリ構成** — API レイヤード構成 + Atomic Design + Web Components
3. **HTMX パターン** — ルーティング規約、部分更新パターン
4. **Web Components 仕様** — 使用基準、コンポーネント設計、プロジェクト固有のコンポーネント一覧
5. **API クライアント / WebSocket** — lib/ の共通ユーティリティ
6. **ビルド構成** — esbuild + Tailwind のビルドパイプライン

既存ドキュメントがある場合は既存の構成・文体に合わせて統合する。

### 5. レビュー

ユーザーに提示し `AskUserQuestion` で確認。フィードバックがあれば修正を繰り返す。

### 6. Commit

CLAUDE.md の規約に従いコミット。

## ルール

- `references/architecture.md` の構成・パターンをベースにする。勝手にパターンを変えない
- プロジェクト固有のコンポーネント名・機能名はヒアリング結果で置き換える
- HALT の設計思想（SPA を作らない、HTMX 優先、Web Components は最小限）を崩す変更はユーザーに確認する
- Mermaid 図でアーキテクチャ概要図を含める
- 既存仕様書の文体・フォーマットに合わせる
