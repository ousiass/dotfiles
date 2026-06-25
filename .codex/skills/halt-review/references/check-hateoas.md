# HATEOAS 準拠チェック

## チェック対象

- Templ テンプレート内の条件付きレンダリング
- Lit コンポーネントの API URL プロパティ
- Templ → Lit の属性渡し

## チェック項目

### 1. 状態駆動レンダリング違反（🟠 Important）

アクション UI（ボタン、リンク、フォーム）が権限・状態に基づいてサーバー側で出し分けられているか確認する。`hidden`、`display:none`、クライアント JS で操作を隠す方式は HATEOAS 違反。

検出方法:
1. `.templ` ファイル内の `hx-post`, `hx-put`, `hx-delete`, `hx-patch` を含む要素を列挙
2. 以下のパターンを違反として検出:
   - `class="hidden"` や `style="display:none"` で囲まれたアクション要素
   - `disabled` 属性が Go の条件式でなく固定値で設定されている要素
   - JavaScript で要素の表示/非表示を切り替えるパターン（`classList.toggle` 等）
3. 正しいパターン: `if` ブロックでアクション要素自体をレンダリングするかしないかを制御

### 2. Lit コンポーネントの URL ハードコード（🟠 Important）

Lit コンポーネントが API パスを内部でハードコードしていないか確認する。URL はサーバー（Templ）から HTML 属性で注入されるべき。

検出方法:
1. `.ts` ファイル内の `api.get(`, `api.post(` 等の呼び出しでパス引数を抽出
2. 以下を違反として検出:
   - テンプレートリテラルで URL を構築: `` api.get(`/api/v1/.../${this.entityId}`) ``
   - 文字列連結で URL を構築: `api.get('/api/v1/...' + this.entityId)`
   - 固定文字列の URL: `api.get('/api/v1/...')`
3. 正しいパターン: `api.get(this.apiUrl)` のようにプロパティ経由で URL を使用

### 3. Templ → Lit の URL 注入漏れ（🟠 Important）

Templ テンプレートが Lit カスタム要素を出力する際に、`api-url` や `ws-url` 属性で API エンドポイントを注入しているか確認する。

検出方法:
1. `.templ` ファイル内のカスタム要素タグ（`<app-prefix-*>`）を検出
2. API 通信を行う Lit コンポーネントに対して `api-url` 属性が渡されているか確認
3. WebSocket を使うコンポーネントに対して `ws-url` 属性が渡されているか確認
4. 権限情報（`readonly` 等）がサーバー側の判定結果として渡されているか確認

### 4. クライアント側の権限判定（🟡 Suggestion）

権限判定がクライアント側（TypeScript / JavaScript）で行われていないか確認する。

検出方法:
1. `.ts` ファイル内の権限チェックパターンを検索:
   - `if (this.role === `, `if (this.permissions.`, `canEdit`, `isAdmin` 等
2. Lit コンポーネントが `role` や `permissions` プロパティを受け取って内部で分岐しているケースを検出
3. 正しいパターン: サーバーが `readonly` 等の結果属性のみを渡し、Lit は判定しない
