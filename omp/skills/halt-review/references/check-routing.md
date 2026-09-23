# ルーティング整合性チェック

## チェック対象

- Go ルーティング定義（`router/`, `handler/` 内の `gin.Engine` / `huma.Register` 呼び出し）
- Templ テンプレート内の HTMX 属性（`hx-get`, `hx-post`, `hx-put`, `hx-patch`, `hx-delete`）
- Lit コンポーネント内の API 呼び出し（`api.get()`, `api.post()` 等）

## チェック項目

### 1. Huma API 登録漏れ（🔴 Critical / 🟠 Important）

JSON API ルート（`/api/v1/...`）が Huma の `Register` で登録されているか確認する。

検出方法:
1. `handler/` 内で `/api/v1/` パスを持つハンドラ関数を列挙
2. `router/` 内の `huma.Register`, `huma.Get`, `huma.Post`, `huma.Put`, `huma.Patch`, `huma.Delete` 呼び出しと照合
3. ハンドラは定義されているが Huma に未登録のルートを検出

重大度:
- Lit コンポーネントから呼ばれているAPIが未登録 → 🔴 Critical（実行時404）
- ハンドラは存在するがどこからも呼ばれていない未登録ルート → 🟠 Important

### 2. HTMX パスとハンドラの不一致（🔴 Critical）

Templ テンプレート内の `hx-*` 属性が指すパスに対応するハンドラが存在するか確認する。

検出方法:
1. `.templ` ファイルから `hx-get="..."`, `hx-post="..."` 等を抽出
2. パスパラメータ（`:id` 等）はワイルドカードとして扱う
3. `router/` のルート定義と照合
4. 一致しないパスを報告

注意: テンプレート内で動的にパスを構築している場合（Go変数の埋め込み）は、変数の型と生成元を追跡して判定する。

### 3. Lit コンポーネントの API パス整合性（🔴 Critical）

Lit コンポーネント内の `api.*()` 呼び出しのパスに対応する API ルートが存在するか確認する。

検出方法:
1. `.ts` ファイルから `api.get(`, `api.post(` 等のパス引数を抽出
2. テンプレートリテラル内のパス（`` `/api/v1/documents/${this.entityId}` ``）も解析
3. Huma 登録済みルートと照合

### 4. SSR / HTMX / API の混在（🟠 Important）

3種のルートが正しく分離されているか確認する。

- SSR ルート（フルHTML返却）: `/` 直下のパス → Gin 直接
- HTMX ルート（HTMLフラグメント返却）: `/` 直下のパス → Gin 直接
- JSON API ルート: `/api/v1/...` → Huma 経由

検出する違反:
- `/api/v1/...` パスが Gin 直接で登録されている（Huma を経由すべき）
- HTMX ルートが JSON を返している（HTML フラグメントを返すべき）
- SSR ルートがフラグメントのみ返している（フルページHTMLを返すべき）

### 5. HTTPメソッドの不一致（🟠 Important）

HTMX 属性のメソッドとハンドラの登録メソッドが一致しているか確認する。

- `hx-get` → `GET` ハンドラ
- `hx-post` → `POST` ハンドラ
- `hx-put` → `PUT` ハンドラ
- `hx-patch` → `PATCH` ハンドラ
- `hx-delete` → `DELETE` ハンドラ
