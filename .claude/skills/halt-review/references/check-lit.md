# Lit Web Components チェック

## チェック対象

- `static/src/components/` 配下の `.ts` ファイル
- Templ テンプレート内のカスタム要素タグ（`<app-prefix-*>`）

## チェック項目

### 1. Web Component の使用基準違反（🟠 Important）

HALT では以下の場合のみ Web Component を作成する:
- リアルタイム編集（ドキュメントエディタ、キャンバス）
- 複雑なドラッグ＆ドロップ（カンバン、並び替え）
- Canvas / WebGL 描画
- WebSocket によるリアルタイム同期

以下は HTMX で処理すべきであり、Web Component にすべきでない:
- 単純なフォーム送信・バリデーション
- リスト表示・フィルタリング・ページネーション
- モーダル表示・非表示
- タブ切り替え
- トースト通知
- 検索フィルタ

検出方法:
1. 各 Web Component の `render()` メソッドと内部ロジックを分析
2. HTMX で代替可能なシンプルなインタラクションのみ実装しているコンポーネントを検出
3. WebSocket、Canvas API、複雑な状態管理を使っていないコンポーネントは疑わしい

### 2. 命名規則違反（🟠 Important）

Web Components は `<app-prefix-feature-name>` 形式で命名する。

検出方法:
1. `@customElement('...')` のタグ名を抽出
2. プロジェクトで統一されたプレフィックスが使われているか確認
3. プレフィックスなし、または不統一なプレフィックスを検出

### 3. lib/api.ts 未使用の直接 fetch（🟠 Important）

Lit コンポーネントは `lib/api.ts` を通じて API を呼ぶべき。直接 `fetch()` を使うと CSRF トークンや認証情報の付与漏れが発生する。

検出方法:
1. コンポーネント内の `fetch(` 呼び出しを検索
2. `lib/api.ts` の import なしに HTTP リクエストしているファイルを検出
3. `XMLHttpRequest` の使用も検出

### 4. SSR/HTMX ルートへの直接アクセス（🟠 Important）

Lit コンポーネントは JSON API（`/api/v1/...`）のみを呼ぶべき。SSR ルートや HTMX ルートを呼ぶと HTML が返り、JSON パースエラーになる。

検出方法:
1. `api.get(`, `api.post(` 等のパス引数を抽出
2. `/api/v1/` で始まらないパスを検出
3. 動的パス構築（テンプレートリテラル）も解析

### 5. ライフサイクル管理（🟡 Suggestion）

適切なライフサイクル管理がされているか確認する。

チェックポイント:
- `connectedCallback()` で `super.connectedCallback()` を呼んでいるか
- `disconnectedCallback()` でイベントリスナーやタイマーをクリーンアップしているか
- WebSocket 接続を `disconnectedCallback()` で切断しているか

### 6. readonly プロパティ対応（🟡 Suggestion）

エディタ系コンポーネントが `readonly` プロパティを受け付け、読み取り専用モードに対応しているか。

検出方法:
1. エディタ系（名前に `editor`, `canvas`, `board` を含む）コンポーネントを特定
2. `@property() readonly` または同等のプロパティが定義されているか確認

### 7. Shadow DOM 使用（🟢 Minor）

Lit コンポーネントが Shadow DOM を使用しているか。`createRenderRoot` をオーバーライドして Shadow DOM を無効化していないか確認する。

HALT では Shadow DOM によるスタイルカプセル化を推奨。
