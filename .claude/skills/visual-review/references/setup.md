# visual-review セットアップと設定スキーマ

## Playwright の導入

プロジェクトの devDependency として入れるのを既定とする。

```bash
# Bun（推奨）
bun add -d playwright && bunx playwright install chromium

# npm を使うプロジェクトの場合
npm i -D playwright && npx playwright install chromium
```

- 既に `@playwright/test` が入っているプロジェクトでは追加導入は不要（`playwright` パッケージが依存に含まれる）
- CI で実行しない前提であれば `chromium` のみで足りる

### package.json が無いプロジェクト（Go / Rails / Django 等）

対象プロジェクトに Node の依存を持ち込みたくない場合は、ユーザー共通の場所に入れる。`capture.mjs` は
`カレントディレクトリ → 設定ファイルの場所 → ~/.cache/visual-review` の順に playwright を探すため、
そこに置けばどのプロジェクトからでも動く。

```bash
mkdir -p ~/.cache/visual-review && cd ~/.cache/visual-review
bun init -y >/dev/null 2>&1 || npm init -y
bun add -d playwright && bunx playwright install chromium
```

**HALT のように esbuild / Tailwind 用の package.json が既にあるプロジェクトでは、そこに入れて構わない。**

## 開発サーバー

`baseUrl` に到達できることが前提。到達確認:

```bash
curl -sS -o /dev/null -w '%{http_code}\n' http://localhost:3000
```

起動していない場合の選択肢:

1. ユーザーに起動を依頼する（`! bun dev` の実行を促す）
2. バックグラウンドで起動する（`run_in_background` で `bun dev` 等）
3. 静的サイトならビルドして配信する（`bun run build && bunx serve dist`）
4. デプロイ済みのプレビュー URL を `baseUrl` にする

## Storybook を対象にする場合

静的ビルドすると story 一覧が JSON で取れるため、対象収集が確実になる。

```bash
bun run build-storybook          # storybook-static/ を生成
bunx serve storybook-static      # 配信
```

- story 一覧: `storybook-static/index.json` の `entries`（各 `id` が iframe URL のクエリになる）
- 撮影 URL: `/iframe.html?id=<story-id>&viewMode=story`
- `#storybook-root` を `waitFor` に指定すると描画完了を待てる

## 設定スキーマ（`.claude/visual-review.json`）

```jsonc
{
  "baseUrl": "http://localhost:3000",   // 必須
  "outDir": ".visual-review",           // 出力先（設定ファイルからの相対パス）

  "viewports": [                        // 既定: desktop / tablet / mobile
    { "name": "desktop", "width": 1440, "height": 900 },
    { "name": "tablet",  "width": 834,  "height": 1112 },
    { "name": "mobile",  "width": 390,  "height": 844 }
  ],

  "themes": [                           // 既定: light のみ
    { "name": "light", "colorScheme": "light" },
    {
      "name": "dark",
      "colorScheme": "dark",            // prefers-color-scheme
      "rootAttribute": ["data-theme", "dark"],  // html 要素の属性（任意）
      "rootClass": "dark",                      // html 要素のクラス（任意）
      "localStorage": { "theme": "dark" }       // 起動前に書き込む値（任意）
    }
  ],

  "fullPage": true,                     // ページ全体を撮る
  "maxSliceHeight": 2000,               // これを超える縦長ページはスライス分割
  "waitForFrontend": true,              // HTMX のスワップ完了と Web Components の描画完了を待つ
  "fragmentWrapper": "<!doctype html>...{{baseUrl}}...{{content}}...",  // フラグメント撮影用ラッパー
  "navigationTimeout": 30000,
  "actionTimeout": 10000,             // waitFor / click 等の待機上限
  "stabilizeDelay": 300,                // 撮影前の待機 ms

  "hide": [".carousel", "[data-testid=now]"],  // 全画面共通で隠すセレクタ

  "auth": {                             // 認証が必要な画面がある場合
    "storageState": "auth.json",        // outDir 配下に保存される
    "login": {
      "steps": [
        { "goto": "/login" },
        { "fill": ["#email", "test@example.com"] },
        { "fill": ["#password", "password"] },
        { "click": "button[type=submit]" },
        { "waitForUrl": "**/dashboard" }
      ]
    }
  },

  "targets": [
    {
      "id": "home",                     // 必須・ファイル名に使われる
      "name": "トップページ",
      "url": "/",                       // baseUrl からの相対、または絶対 URL
      "origin": "route",                // config / storybook / route / spec / mock
      "mock": "mocks/home.html",        // モック（文字列 or { "path" } / { "url" }）
      "waitUntil": "networkidle",       // load / domcontentloaded / networkidle
      "fragment": false,                // true にすると HX-Request 付きで取得した部分 HTML を撮る
      "waitFor": "main",                // このセレクタが出るまで待つ
      "hide": [".hero-video"],          // この画面だけ隠すセレクタ
      "fullPage": true,
      "actions": [                      // 状態を再現する操作
        { "click": "[data-testid=open-filter]" },
        { "waitFor": "[role=dialog]" }
      ]
    },
    {
      "id": "button-loading",
      "name": "Button / Loading",
      "url": "/iframe.html?id=components-button--loading&viewMode=story",
      "origin": "storybook",
      "waitFor": "#storybook-root"
    }
  ]
}
```

### `actions` / `login.steps` の DSL

1 ステップ 1 キー。実行は記述順。

| キー | 値 | 動作 |
|-----|---|-----|
| `goto` | URL | 遷移 |
| `click` | セレクタ | クリック |
| `fill` | `[セレクタ, 値]` | 入力 |
| `press` | `[セレクタ, キー]` | キー押下（例 `["#q", "Enter"]`） |
| `waitFor` | セレクタ | 要素の出現を待つ |
| `waitForUrl` | URL パターン | URL 遷移を待つ |
| `wait` | ミリ秒 | 固定待機（最後の手段） |
| `scrollTo` | Y 座標 | スクロール |

## HALT（HTMX + Atomic Design + Lit + Templ）プロジェクト

Go サーバー内蔵型の構成。JS フレームワークのルーティング規約が無いため、以下の点が他と異なる。

### 1. 対象の収集

- ページルートは `backend/internal/router/` の Gin 登録から抽出する（`GET` のみ）
- `/api/v1/...`（Huma 経由の JSON）は視覚レビュー対象外
- **アクションルート（POST / PUT / DELETE）は撮影しない。** 副作用でデータを壊す
- templ コンポーネント（`web/atoms/`, `molecules/`, `organisms/`）は Go 関数なので単体 URL が無い。
  コンポーネント単体の見た目は**フラグメント撮影**で代替する（下記）

### 2. dev サーバーの起動

`bun dev` ではない。プロジェクトの慣習を確認する。

```bash
make dev          # Makefile がある場合はこれが多い
air               # ホットリロード付き
go run ./cmd/server
```

ポートは 8080 系が多い。`baseUrl` を実際の待ち受けポートに合わせる。

### 3. ビルド成果物の鮮度確認（重要）

HALT は CSS / JS をビルドして `static/dist/` から配信する。**ビルドが古いと実描画がソースと食い違い、
レビュー結果が無効になる。** 撮影前に必ず確認する。

```bash
templ generate                      # .templ → _templ.go（テンプレート変更時）
bun run build                       # esbuild（Web Components）+ Tailwind CSS
# または
make build-frontend
```

`static/src/` と `static/dist/` の mtime を比較し、`dist/` が古ければビルドしてから撮影する。

### 4. フラグメント撮影

HTMX が返す部分 HTML を単体で描画して撮影する。HALT のページルートは `HX-Request` ヘッダーで
フルページとフラグメントを分岐するため、**同じ URL から両方の見た目が撮れる**。

```jsonc
{
  "id": "tasks",
  "name": "タスク一覧（フルページ）",
  "url": "/projects/1/tasks",
  "origin": "route"
},
{
  "id": "tasks-fragment",
  "name": "タスク一覧（フラグメント）",
  "url": "/projects/1/tasks",
  "fragment": true,
  "origin": "fragment"
}
```

フラグメントには `<head>` が無いため、ラッパーに埋め込んで撮影する。既定のラッパーは
`/static/dist/css/app.css` を読み込むので、**配信パスが違う場合は `fragmentWrapper` を上書きする**。

```jsonc
{
  "fragmentWrapper": "<!doctype html><html><head><base href=\"{{baseUrl}}\"><link rel=\"stylesheet\" href=\"/assets/app.css\"><script src=\"/assets/js/doc-editor.js\" type=\"module\"></script></head><body class=\"p-6\">{{content}}</body></html>"
}
```

- `{{baseUrl}}` → `baseUrl`、`{{content}}` → 取得したフラグメント HTML に置換される
- Lit コンポーネントを含むフラグメントを撮る場合は、**ラッパーにそのバンドルの `<script>` を入れる**（入れないと空で描画される）
- `<body class="...">` に本来の親要素のクラス（背景色・余白）を与えると、単体でも実際に近い見た目になる

### 5. Lit Web Components

`waitForFrontend`（既定 `true`）が `customElements.whenDefined()` と各要素の `updateComplete` を待つため、
通常は追加設定なしで描画完了後に撮影される。

- **カスタム要素が空で撮影される場合**、ほぼビルド未実行・JS エラー・バンドル未読み込みのいずれか。
  デザインの問題として報告する前に切り分ける
- shadow DOM 内部にも `hide` とアニメーション停止 CSS は注入されるが、`::part` を持たない内部要素の
  細かな制御はできない

### 6. HTMX の待機

`waitForFrontend` が `.htmx-request` / `.htmx-swapping` / `.htmx-settling` が消えるまで待つ。
`hx-trigger="load"` の遅延ロードがある画面では、`waitFor` に**遅延ロード後に現れる要素**を指定する。

```jsonc
{ "id": "dashboard", "url": "/dashboard", "waitFor": "#activity-list li" }
```

`actions` で操作後の状態を撮る場合も、スワップ完了は自動で待たれる。

```jsonc
"actions": [
  { "click": "button[hx-post='/tasks/1/status']" },
  { "waitFor": "#task-1[data-status='done']" }
]
```

### 7. 認証（Cookie セッション + CSRF）

`storageState` に Cookie が保存されるため通常どおり動く。ただしログインが HTMX 経由の場合、
`HX-Redirect` ヘッダーでの遷移は `waitForUrl` で捕まえられないことがある。**遷移後に現れる要素を
`waitFor` で待つ**。

```jsonc
"auth": {
  "storageState": "auth.json",
  "login": {
    "steps": [
      { "goto": "/login" },
      { "fill": ["input[name=email]", "dev@example.com"] },
      { "fill": ["input[name=password]", "password"] },
      { "click": "button[type=submit]" },
      { "waitFor": "[data-testid=sidebar]" }
    ]
  }
}
```

## モックの置き場所

`mocks/`, `mock/`, `docs/mocks/`, `design/mocks/`, `.mocks/` を探索する（`__mocks__/` はテスト用途のためスキップ）。

- **HTML モック**: 実装と同じビューポートで撮影される。相対パスの CSS / 画像は `file://` で解決されるため、モックが単体で開けることを確認する
- **画像カンプ**（`.png` / `.jpg` / `.webp` 等）: 撮影せずレビュー時に直接読み込む
- **Markdown モック**: 画像化せず本文を照合する
- **URL モック**: 公開プレビュー URL を `{ "url": "..." }` で指定する

## 撮影成果物の除外

`outDir`（既定 `.visual-review`）は `.gitignore` に追加する。

```
.visual-review/
```

## トラブルシュート

| 症状 | 対処 |
|-----|-----|
| スクショが真っ白 | `waitFor` に主要要素のセレクタを指定する。`waitUntil` を `networkidle` にする |
| 撮影ごとに差分が出る | `hide` に日時・カルーセル・ランダム表示のセレクタを追加する |
| ダークテーマが効かない | `colorScheme` だけでなく `rootAttribute` / `rootClass` / `localStorage` を実装方式に合わせて指定する |
| ログイン画面にリダイレクトされる | `--auth` を再実行して `storageState` を作り直す |
| 画像が巨大でレビューしづらい | `maxSliceHeight` を下げる、または `fullPage: false` にする |
| フォントが毎回違う | `document.fonts.ready` 待ちは実装済み。`stabilizeDelay` を増やす |
| フラグメントがスタイルなしで撮れる | `fragmentWrapper` の CSS パスを実際の配信パスに合わせる |
| カスタム要素が空で撮れる | フロントエンドをビルドする。フラグメント撮影時はラッパーに `<script>` を入れる |
| templ の変更が反映されない | `templ generate` を実行してサーバーを再起動する |
