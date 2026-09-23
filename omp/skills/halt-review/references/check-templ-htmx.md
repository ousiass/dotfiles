# Templ ↔ HTMX 接続チェック

## チェック対象

- `.templ` ファイル内の HTMX 属性
- Go ハンドラのレスポンス（`c.HTML()`, `c.JSON()`, `templ.Handler()`, `component.Render()` 等）

## チェック項目

### 1. HTMX レスポンスが HTML フラグメントを返しているか（🔴 Critical）

HTMX ルートのハンドラが Templ で HTML フラグメントを返しているか確認する。JSON を返している場合は HALT 違反。

検出方法:
1. HTMX パスに対応するハンドラ関数を特定
2. ハンドラのレスポンスが以下のいずれかであることを確認:
   - `component.Render(ctx, c.Writer)` — Templ コンポーネントのレンダリング
   - `templ.Handler(component)` — Templ ハンドラ
   - `c.HTML(...)` で Templ 生成の HTML を返却
3. `c.JSON()` や `json.NewEncoder` でレスポンスを返しているHTMXハンドラを検出

### 2. SSR ルートがフルページ HTML を返しているか（🟠 Important）

SSR ルート（初回ページロード）のハンドラが `layout` でラップされたフルページ HTML を返しているか確認する。

検出方法:
1. SSR ルート（`GET /workspaces`, `GET /projects/:id` 等のページルート）のハンドラを特定
2. レスポンスで `layout` パッケージのコンポーネントが使われているか確認
3. フラグメントのみ返しているSSRルートを検出

### 3. hx-swap / hx-target の整合性（🟡 Suggestion）

`hx-swap` の値とレスポンスの構造が整合しているか確認する。

チェックポイント:
- `hx-swap="outerHTML"` → レスポンスがトリガー要素と同等の構造を返すべき
- `hx-swap="innerHTML"` → レスポンスが子要素のみ返すべき
- `hx-target` が指定されている場合 → ターゲット要素の ID がテンプレート内に存在するか

### 4. hx-vals / hx-include の妥当性（🟡 Suggestion）

`hx-vals` で送信するデータがハンドラの入力構造体と整合しているか確認する。

検出方法:
1. `hx-vals='{"key":"value"}'` のキーを抽出
2. 対応するハンドラのリクエスト構造体（バインド先）のフィールドと照合
3. 不一致のキーを報告

### 5. HTMX トリガー設定の妥当性（🟢 Minor）

`hx-trigger` の設定が意図通りか確認する。

- フォーム送信に `hx-trigger="submit"` が明示されているか（省略時はデフォルト動作に依存）
- `hx-trigger="change"` が適切な要素（input, select）に使われているか
- デバウンス（`delay:500ms`）が検索入力等に適用されているか
