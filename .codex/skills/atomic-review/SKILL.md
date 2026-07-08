---
name: atomic-review
description: Atomic Design 準拠レビューを行う（Atomic Design 構造、命名・prop・composition 品質、Next.js / Nuxt v3・v4 固有ルール）。ユーザーが Next.js / Nuxt / React / Vue の Atomic Design プロジェクトに対して構造監査・レビュー・リファクタ候補抽出を依頼したときに使う。
---

# atomic-review

Atomic Design で構築された Next.js / Nuxt v3・v4 / React / Vue プロジェクトを、Atomic Design 構造・命名/composition 品質・フレームワーク固有ルールの観点でレビューする。

## 前提条件

- Codex CLI 環境
- `gh` CLI（GitHub Issue 出力時）
- 対象プロジェクトが Atomic Design 準拠のディレクトリ構成であること（`atoms/`, `molecules/`, `organisms/`, `pages/` または `templates/`）

## 引数

- 引数なし: カレントディレクトリのプロジェクト全体をチェック
- パス指定: 指定したディレクトリまたはファイルのみチェック

## Phase 1: プロジェクト構造とフレームワークの検出

1. `package.json` の dependencies を読み、フレームワークとメジャーバージョンを判定する
   - `next` あり + `next.config.*` あり → **Next.js**
   - `nuxt` の major が `3.x` → **Nuxt v3**
   - `nuxt` の major が `4.x` 以上、または `nuxt.config.*` に `future.compatibilityVersion: 4` 指定あり → **Nuxt v4**
   - `react` あり + `vite` あり（`next` なし）→ **素の React**
   - `vue` あり + `vite` あり（`nuxt` なし）→ **素の Vue**
2. Atomic Design レイヤーのルートを特定する（優先順）
   - `src/components/{atoms,molecules,organisms,pages,layout}/`
   - `components/{atoms,molecules,organisms,pages,layout}/`
   - `app/components/{...}`（Next.js App Router / Nuxt v4 の srcDir 既定）
   - Nuxt v3 の場合、Atomic の `pages/` はフレームワークの `pages/` と衝突するため `components/pages/` 配下に置かれる想定
   - Nuxt v4 の場合、`app/components/`, `app/pages/`, `app/layouts/`, `app/composables/` が既定。Atomic の `pages/` は `app/components/pages/` に置かれる想定
3. 対象拡張子を確定する
   - Next.js / React: `.tsx`, `.jsx`, `.ts`, `.js`
   - Nuxt / Vue: `.vue`
4. チェック項目ごとに進捗を管理する

## Phase 2: レビュー実行

全チェック観点を順に実行する。**対象ファイルはすべてチェックする。** ファイル数が多い場合はディレクトリ単位で分割して処理する。

チェック観点の詳細:
- Atomic Design 構造（依存方向・配置妥当性・layout 使用・未使用）: `references/check-structure.md`
- コンポーネント品質（命名・prop drilling・composition）: `references/check-quality.md`
- Next.js 固有（'use client' 境界・App/Pages Router 共存）: `references/check-nextjs.md`
- Nuxt 固有（auto-import・composables/・pages/layouts 共存、v3/v4 の srcDir 差異）: `references/check-nuxt.md`

FW 固有チェックは Phase 1 で検出したフレームワークに対応するもののみ実行する。素の React / Vue の場合は FW 固有チェックをスキップする。Nuxt v3 と v4 の差異は `check-nuxt.md` 内で分岐して扱う。

## Phase 3: レポート生成

1. 選択式でユーザーに出力先を確認する（自由入力を許容）:
   - **GitHub Issue**（推奨）: タイトル `atomic-review: Atomic Design レビュー (<branch>, <YYYY-MM-DD>)`
   - **ローカル MD ファイル**: `atomic-review-report.md`
   - **コンソール出力**: 会話に直接レポート表示
2. `templates/report.md` のフォーマットを使用（検出したフレームワーク名をヘッダに含める）
3. サマリーをユーザーに報告

## 重大度基準

| 重大度 | 基準 |
|--------|------|
| Critical | Atomic 依存方向の完全逆転（atoms が pages を import）、Next.js の Server Component から Client-only モジュール直呼び、Client Component から Server 専用モジュール参照 |
| Important | 配置層とコンポーネント複雑度のミスマッチ、layout の非 pages 層からの直接使用、命名規則の不統一、深い prop drilling（3 段以上）、'use client' の過剰付与、Nuxt composables/ に置くべきロジックが components/ にある |
| Suggestion | HTMX/RSC フラグメント配置の最適化、composition パターン改善、Nuxt auto-import 想定外パス |
| Minor | 未使用コンポーネント、スタイル統一、軽微な命名改善 |

## ルール

- 推測で指摘しない。実際のコードを検証して報告する
- 指摘には必ずファイルパスと行番号を含める
- 具体的な改善案を提示する
- Critical / Important は必ず含める。Suggestion / Minor は明確なメリットがある場合のみ
- プロジェクト固有の慣習や既存コードスタイルを尊重する
- 計画立てしつつ進捗を管理する
