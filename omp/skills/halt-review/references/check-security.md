# セキュリティチェック

## チェック対象

- Go ハンドラ・ミドルウェア
- Lit コンポーネントの API クライアント
- Templ テンプレートの meta タグ・フォーム

## チェック項目

### 1. CSRF トークン未適用（🔴 Critical）

状態変更リクエスト（POST/PUT/PATCH/DELETE）に CSRF トークンが含まれているか確認する。

検出方法:
1. **Templ テンプレート**: `<meta name="csrf-token"` がレイアウトテンプレートに存在するか
2. **HTMX リクエスト**: HTMX の設定で CSRF ヘッダーが自動付与されているか
   - `hx-headers` や `htmx.config.getCacheBusterParam` の設定
   - または `document.body` の `hx-headers` 属性でグローバル設定
3. **lib/api.ts**: CSRF トークンを meta タグから取得してヘッダーに含めているか
4. **Go ミドルウェア**: CSRF 検証ミドルウェアが状態変更ルートに適用されているか

### 2. 認証ミドルウェア未適用（🔴 Critical）

認証が必要なルートにミドルウェアが適用されているか確認する。

検出方法:
1. ルーティング定義で認証ミドルウェア（`AuthRequired`, `RequireAuth` 等）のグループを特定
2. 保護すべきルート（ユーザーデータ操作、設定変更等）が認証グループ外にないか確認
3. 公開ルート（ログイン、登録、ヘルスチェック）のみが認証なしであることを確認

### 3. credentials 設定漏れ（🟠 Important）

`lib/api.ts` で `credentials: 'same-origin'` が設定されているか確認する。

Cookie ベースのセッション認証では `credentials` 設定がないと Cookie が送信されない。

### 4. Templ の自動エスケープ確認（🟡 Suggestion）

Templ はデフォルトでHTML自動エスケープを行うが、`templ.Raw()` の使用箇所を確認する。

検出方法:
1. `templ.Raw(` の使用箇所を検索
2. ユーザー入力由来のデータが `templ.Raw()` に渡されていないか確認
3. 正当な用途（静的HTML、マークダウンレンダリング済みコンテンツ等）を除外

### 5. API キー / Bearer トークンの管理（🟡 Suggestion）

JSON API 用の認証トークンがハードコードされていないか確認する。

検出方法:
1. `.ts`, `.go` ファイル内のハードコードされたトークン文字列を検索
2. 環境変数や設定ファイルから読み込まれているか確認
