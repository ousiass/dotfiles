---
name: mock-drift
description: モックと実装の乖離をコンポーネント単位でチェックし、レポートを生成する。
user-invocable: true
---

# mock-drift

モックディレクトリに置かれた HTML/CSS または Markdown 形式の UI モックと、実装コードとの乖離をコンポーネント単位で検出する。構造（DOM・要素・テキスト）とデザイントークン（色・タイポグラフィ・スペーシング）の両面をチェックする。

## 前提条件

- Claude Code 環境
- `gh` CLI（GitHub Issue 出力時）
- モックが `mocks/`, `docs/mocks/`, `design/mocks/` 等の固定ディレクトリに配置されていること

## 引数

- 引数なし: モックディレクトリを自動検出
- パス指定: 指定したモックディレクトリまたはモックファイルのみ対象

## Phase 1: モック位置とデザイン基盤の検出

1. モックディレクトリを以下の優先順で探索
   - `mocks/`, `mock/`
   - `docs/mocks/`, `design/mocks/`
   - `.mocks/`（`__mocks__/` はテスト用途のためスキップ）
2. デザイン基盤ファイルを検出
   - `tailwind.config.*`, `uno.config.*`
   - `theme.ts`, `tokens.*`, `variables.css`, `design-tokens.*`
   - グローバルスタイル（`global.css`, `base.css`, `app.css`）
3. 実装コードの対象拡張子を判定
   - React: `.tsx`, `.jsx`
   - Vue: `.vue`
   - Shopify: `.liquid`
   - HALT: `.templ`
   - その他: `.html`, `.ejs`, `.pug`, `.svelte`, `.astro`
4. モックが見つからなければユーザーに `AskUserQuestion` で確認する

## Phase 2: モックと実装のマッピング

1. モックファイルごとに、ファイル名（拡張子を除いた basename）で実装ファイルを検索
   - 例: `mocks/Button.html` → `**/Button.{tsx,vue,jsx,liquid,templ,svelte,astro}`
   - 例: `mocks/atoms/Card.md` → `**/Card.*`
2. マッピング結果を `TaskCreate` でタスク化。1 モック = 1 タスク
3. マッチする実装が見つからない場合は「未実装」として記録
4. 複数マッチした場合はディレクトリの近さ（Atomic Design 階層等）で優先

## Phase 3: 乖離チェック（1 件ずつ）

各ペアを 1 件ずつ順に検証し、進捗を `TaskUpdate` で更新する。詳細な観点は `references/check-criteria.md` を参照。

### 3.1 構造チェック（HTML モック）

- 主要な DOM 要素（heading, button, form, list 等）がモックと実装に存在するか
- テキストラベル・placeholder・alt・aria-label がモックと一致するか
- 要素の階層関係（親子・兄弟）が保たれているか
- 状態表現（disabled, loading, empty, error）がモックに描かれていれば実装にも存在するか
- **ナビゲーション / メニュー**: 項目の網羅・順序・ラベル・リンク先・サブメニュー階層・アクティブ状態・モバイル用メニュー・パンくずがモックと一致するか

### 3.2 構造チェック（Markdown モック）

- 見出し・箇条書きで記述された UI 要素が実装に存在するか
- 記載された Props / バリアント / 状態が実装に存在するか

### 3.3 デザイントークンチェック

- モック側のスタイル/クラスから抽出したデザイン値（色・spacing・font-size・radius・shadow）が実装側と一致するか
- 実装側でハードコード値が使われていないか（Phase 1 で検出したトークンに引き当てる）
- Tailwind 等ユーティリティ CSS 使用時は同一トークン名（例: `bg-primary-500`）を参照しているか
- タイポグラフィ（font-family, font-weight, line-height）が一致するか

## Phase 4: レポート生成

1. `AskUserQuestion` で出力先を確認
   - **GitHub Issue**（推奨）: タイトル `mock-drift: モック乖離レポート(<branch>, <YYYY-MM-DD>)`
   - **ローカル MD ファイル**: `mock-drift-report.md`
   - **コンソール出力**: 会話に直接出力
2. `templates/report.md` のフォーマットを使用
3. 要約をユーザーに報告

## 重大度基準

| 重大度 | 基準 |
|--------|------|
| 🔴 Critical | モックの主要要素が実装に存在しない、または実装がモックと明確に矛盾（機能欠落・誤配置） |
| 🟠 Important | デザイントークン違反（ハードコード値）、モック未定義の要素追加、状態欠如（hover/disabled 等） |
| 🟡 Suggestion | 軽微なスタイルズレ、改善余地のあるトークン化、アクセシビリティ強化 |
| 🟢 Minor | 表記ゆれ、命名の細部、コード整理 |

## ルール

- 推測で乖離を報告しない。モックと実装両方を確認して裏付けを取る
- 指摘にはモック側（ファイルパスと該当箇所）と実装側（ファイルパス:行番号）の両方を示す
- モックを「あるべき姿」の参照とする。ただし、モックが古く実装側の変更が妥当な場合は「モックを更新」を推奨として明記する
- デザイン基盤ファイル未検出時は、モック側の値をそのまま基準とする
- 🔴🟠 は必ずレポートに含める。🟡🟢 は明確なメリットがある場合のみ
- テスト用モック（`__mocks__/`, `*.spec.mock.*`）は対象外
- `TaskCreate` / `TaskUpdate` で進捗を管理する
