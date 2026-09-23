# HALT アーキテクチャ リファレンス

HTMX + Atomic Design + Lit + Templ によるサーバー内蔵型フロントエンドアーキテクチャ。

## 設計思想

バックエンドファースト。判断に迷ったらサーバー側に寄せる。

- フロントエンドはAPIサーバーの中で動く。SPA は作らない
- サーバーがUI制御を握り、HTMX でハイパーメディア駆動のインタラクションを実現する
- リッチなインタラクションが必要な箇所だけ Lit Web Components で拡張する
- テンプレートは Atomic Design で構造化する
- クライアント側の状態・ロジックは最小限に留める。状態はサーバーが持つ
- 各技術は疎結合に組み合わせる。特定技術への依存を最小化し、差し替え可能に保つ
- **HATEOAS**: サーバーのレスポンスに含まれるハイパーメディアコントロール（リンク、フォーム、ボタン）が、次に何ができるかをクライアントに伝える。クライアントは URL をハードコードしない

### 状態駆動レンダリング（HATEOAS 原則）

サーバーが現在の状態と権限に基づいて、**利用可能なアクションのみを HTML に含める**。クライアントは「UIの存在 ＝ 操作可能」と判断する。

- ボタンが見えるなら押せる。見えないなら存在しない
- `hidden` や `disabled` で操作を隠すのではなく、**レンダリングしない**のが正しい
- 権限判定はサーバー（Go）側で行い、テンプレートに結果を渡す

```go
// ✅ サーバーが権限に基づきアクションを出し分ける
templ TaskRow(task domain.Task, perms Permissions) {
    <tr id={ fmt.Sprintf("task-%s", task.ID) }>
        <td>{ task.Title }</td>
        <td>
            if perms.CanUpdateStatus {
                <button hx-post={ fmt.Sprintf("/tasks/%s/status", task.ID) }
                        hx-target={ fmt.Sprintf("#task-%s", task.ID) }
                        hx-swap="outerHTML">
                    完了にする
                </button>
            }
            if perms.CanDelete {
                <button hx-delete={ fmt.Sprintf("/tasks/%s", task.ID) }
                        hx-target={ fmt.Sprintf("#task-%s", task.ID) }
                        hx-swap="outerHTML">
                    削除
                </button>
            }
        </td>
    </tr>
}
```

この原則は Templ テンプレートだけでなく、Lit コンポーネントへの属性渡しにも適用する（後述「Lit への URL・権限注入」）。

## 技術スタック

| レイヤー | 技術 | 役割 |
|---------|------|------|
| サーバーフレームワーク | Go + Gin | ルーティング + SSR |
| API フレームワーク | Huma | OpenAPI 3.1 自動生成、入出力バリデーション |
| テンプレートエンジン | Templ | 型安全な Go HTML テンプレート |
| インタラクション | HTMX | サーバー駆動の DOM 更新 |
| リッチUI | Lit (Web Components) | エディタ等の高度なインタラクション |
| スタイリング | Tailwind CSS | ユーティリティファースト CSS |
| ビルド | esbuild | TypeScript バンドル |

## ディレクトリ構成

### APIサーバー（レイヤードアーキテクチャ）

```
backend/
├── cmd/                    # エントリーポイント
├── internal/
│   ├── domain/             # ドメインモデル・ビジネスロジック
│   ├── repository/         # データアクセス層
│   ├── service/            # アプリケーションサービス層
│   ├── router/             # ルーティング定義（SSR + API）
│   └── web/                # Web層（以下詳細）
│       ├── handler/        # HTTPハンドラ（機能ドメイン別）
│       │   ├── auth.go
│       │   ├── workspace.go
│       │   ├── project.go
│       │   ├── task.go
│       │   ├── document.go
│       │   └── ...
│       ├── middleware/      # 共通ミドルウェア
│       ├── atoms/          # 基本要素（button, input, badge, avatar 等）
│       ├── molecules/      # 複合要素（card, modal, tag_select 等）
│       ├── organisms/      # 機能単位（header, sidebar, command_palette 等）
│       ├── pages/          # ページテンプレート
│       └── layout/         # レイアウトラッパー
└── static/
    └── src/
        ├── components/     # Lit Web Components（後述）
        │   └── lib/        # 共通ユーティリティ
        ├── css/            # Tailwind CSS エントリーポイント
        └── dist/           # ビルド成果物
```

### レイヤー依存ルール

依存は上から下への一方向のみ。逆方向の import は禁止。

```
handler  → service → repository → domain
   ↓
 Templ テンプレート（atoms/molecules/organisms/pages）
```

- `domain/`: 他のレイヤーに依存しない。純粋なビジネスロジック
- `repository/`: `domain/` のみに依存
- `service/`: `domain/`, `repository/` に依存
- `web/handler/`: `service/`, `domain/` に依存。`repository/` を直接使わない
- `router/`: `handler/` を参照してルートを定義

### Lit Web Components

エディタ等、リッチなインタラクションが必要な箇所のみ Web Components として実装する。

```
src/components/
├── {feature-name}/         # 機能単位のコンポーネント
│   └── {feature-name}.ts   # Lit カスタム要素
└── lib/
    ├── api.ts              # HTTP クライアント（CSRF トークン自動付与）
    ├── ws.ts               # WebSocket ラッパー（自動再接続）
    └── logger.ts           # ロギングユーティリティ
```

**命名規則**: `<app-prefix>-{feature-name}` （例: `<my-doc-editor>`, `<my-kanban-board>`）

### ビルド成果物

```
dist/
├── js/
│   ├── {component-name}.js  # 各 Web Component のバンドル
│   └── htmx.min.js          # HTMX ライブラリ
└── css/
    └── app.css               # Tailwind CSS ビルド済み
```

## Templ テンプレート（Atomic Design）

### atoms（原子）

最小のUI要素。単一の責務を持つ。

- button, input, textarea, select
- avatar, badge, spinner
- toast（通知トースト）

### molecules（分子）

atoms を組み合わせた複合要素。

- card, modal
- tag_select, task_row
- doc_item

### organisms（有機体）

molecules と atoms を組み合わせた機能単位。

- header, sidebar
- notification_list
- document_tree_node
- command_palette

### pages（ページ）

organisms を組み合わせたページ全体のテンプレート。

- login, register
- workspace 一覧・詳細
- project 一覧・詳細
- document エディタ、canvas エディタ
- settings

### コンポーネントインターフェース規約

Go の型安全性をフル活用する。

**単純なコンポーネント**（引数3個以下）— 直接パラメータ:

```go
templ Button(text string, variant ButtonVariant, disabled bool) {
    <button class={ buttonClass(variant) } disabled?={ disabled }>{ text }</button>
}
```

**複雑なコンポーネント** — Props 構造体:

```go
type CardProps struct {
    Title    string
    Subtitle string
    ImageURL string
    Actions  []Action
    Attrs    templ.Attributes  // HTML属性パススルー
}

templ Card(props CardProps) { ... }
```

**バリエーション** — Go の const + カスタム型で型安全に:

```go
type ButtonVariant string

const (
    ButtonPrimary   ButtonVariant = "primary"
    ButtonSecondary ButtonVariant = "secondary"
    ButtonDanger    ButtonVariant = "danger"
)
```

**子要素スロット** — `templ.Component` パラメータ:

```go
templ Modal(title string) {
    <div class="modal">
        <h2>{ title }</h2>
        <div class="modal-body">
            { children... }
        </div>
    </div>
}
```

## HTMX パターン

### 基本方針

- サーバーが HTML フラグメントを返し、HTMX が DOM を差し替える
- JSON API は外部クライアント向け。HTMX は HTML エンドポイントを使う
- フォーム送信、リスト更新、モーダル管理は HTMX で処理する

### ルーティング（3パターン）

```
# ページルート — Gin 直接、HX-Request ヘッダーで分岐
GET  /workspaces                → フルページ or フラグメント
GET  /projects/:id/tasks        → フルページ or フラグメント
GET  /documents/:id/edit        → フルページ（Lit Component 埋め込み）

# アクションルート — Gin 直接、常にフラグメント返却
PUT  /notifications/read-all    → 通知リスト部分 HTML
POST /tasks/:id/status          → タスク行 HTML
DELETE /tasks/:id               → 空レスポンス or 更新後リスト

# API ルート — Huma 経由（JSON + OpenAPI 自動生成）
GET  /api/v1/workspaces         → JSON レスポンス
POST /api/v1/tasks              → JSON レスポンス
GET  /api/v1/openapi.json       → OpenAPI 3.1 スペック（Huma 自動生成）
```

| パターン | URL | HX-Request 分岐 | 返却 | 登録先 |
|---------|-----|-----------------|------|--------|
| ページルート | `/workspaces` 等 | する | フルページ or フラグメント | Gin |
| アクションルート | `/tasks/:id/status` 等 | しない | フラグメントのみ | Gin |
| API ルート | `/api/v1/...` | しない | JSON | Huma |

**ページルートの HX-Request 分岐**:

```go
func (h *TaskHandler) List(c *gin.Context) {
    tasks := h.service.ListTasks(c.Request.Context())
    if c.GetHeader("HX-Request") != "" {
        // HTMX リクエスト → フラグメントのみ
        organisms.TaskList(tasks).Render(c.Request.Context(), c.Writer)
    } else {
        // 通常アクセス → layout 込みフルページ
        pages.TaskListPage(tasks).Render(c.Request.Context(), c.Writer)
    }
}
```

この方式により同じ URL でブラウザの直接アクセスと HTMX 部分更新の両方に対応できる。

### OOB（Out of Band）スワップ

1レスポンスで複数 DOM 領域を更新する機能。**副作用の反映のみ**に使い、メインコンテンツの更新には使わない。

**使ってよい場面:**
- メイン操作の副作用（例: タスク完了 → ヘッダーの通知カウンタ更新）
- トースト通知の表示

**使わない場面:**
- メインコンテンツの更新（`hx-target` で直接指定すべき）
- 3箇所以上の同時更新（設計を見直すサイン）

```html
<!-- メインレスポンス: タスク行の更新 -->
<tr id="task-123" class="completed">...</tr>

<!-- OOB: 通知カウンタの副作用更新 -->
<span id="task-count" hx-swap-oob="true">残り 4 件</span>
```

### ローディング・遷移状態

サーバーが真実。応答を待つのが正しい姿勢。Optimistic UI は使わない。

- **部分更新**: `hx-indicator` で対象要素にスピナー atom を表示
- **ページ遷移**: `hx-boost` + グローバルプログレスバー
- **二重送信防止**: `hx-disabled-elt="this"` でボタンを無効化
- **スケルトンスクリーンは使わない**（SPA の手法。サーバー応答は十分速い）

```html
<button hx-post="/tasks/123/status"
        hx-indicator="#task-123-spinner"
        hx-disabled-elt="this">
  完了にする
</button>
<span id="task-123-spinner" class="htmx-indicator">
  @atoms.Spinner("sm")
</span>
```

### HTMX 拡張

ミニマリズムを優先する。必要になるまで入れない。

| 拡張 | 採否 | 理由 |
|------|------|------|
| `response-targets` | 推奨 | エラーレスポンスの表示先をステータスコード別に分けられる |
| `hx-boost` | 必要に応じて | ページ遷移のSPA風体験。グローバルに有効化しすぎない |
| `preload` | 非推奨 | 不要なリクエスト増。サーバー負荷 |
| `loading-states` | 非推奨 | `hx-indicator` で十分 |

## HTMX ↔ Lit 境界ルール

HTMX がページ全体を制御し、Lit コンポーネントは**アイランド（島）**として埋め込まれる。互いの領域を侵さない。

```
┌──────────────────────────────────────┐
│  HTMX ゾーン（サーバー制御）           │
│                                      │
│  ┌─ hx-target ──┐  ┌─────────────┐  │
│  │ HTMX 部分更新 │  │ Lit アイランド │  │
│  │ ↕ HTML       │  │ ↕ JSON API  │  │
│  └──────────────┘  └─────────────┘  │
│                                      │
│        ↕ HTML フラグメント             │
└──────────────────────────────────────┘
```

### 基本ルール

1. **HTMX は Lit コンポーネントを含む DOM 領域を swap しない**。コンポーネント破棄 = 内部状態の消失
2. **Lit は HTMX リクエストをトリガーしない**。Lit は JSON API の世界に住む
3. **Lit コンポーネントの外側に `hx-target` を配置しない**。swap 範囲を Lit の外に制限する

### 連携パターン

**Lit → HTMX（間接連携）:**

Lit が CustomEvent を発火 → HTMX が `hx-trigger` でキャッチ → サーバーに問い合わせ → HTML 更新。**サーバーを経由**することで「サーバーがUI制御」を維持する。

```html
<!-- Templ テンプレート: Lit の外側で HTMX が CustomEvent をリスン -->
<div hx-get="/tasks/list"
     hx-trigger="taskUpdated from:closest .task-container"
     hx-target="#task-list">
  <div id="task-list">
    @organisms.TaskList(tasks)
  </div>
  <app-task-editor task-id={ taskID }></app-task-editor>
</div>
```

```typescript
// Lit コンポーネント: 保存完了時に CustomEvent を発火
this.dispatchEvent(new CustomEvent('taskUpdated', {
  bubbles: true, composed: true
}));
```

**HTMX → Lit:**

Lit コンポーネントの**HTML属性を更新**する（コンポーネント自体は swap しない）。Lit の Reactive Properties が変更を検知して再レンダリングする。

やむを得ず Lit を含む領域を swap する場合は、Lit コンポーネントの再マウントを許容する設計にする（`connectedCallback` でデータを再取得）。

## Lit Web Components パターン

### 使用基準

以下に該当する場合のみ Web Component を作成する：

- リアルタイム編集（ドキュメントエディタ、キャンバス）
- 複雑なドラッグ＆ドロップ（カンバン、並び替え）
- Canvas / WebGL 描画
- WebSocket によるリアルタイム同期

HTMX で十分なインタラクション（フォーム、リスト更新、モーダル等）には Web Component を使わない。

### コンポーネント設計

```typescript
@customElement('my-feature-name')
export class MyFeatureName extends LitElement {
  // サーバーから注入される URL・設定（HATEOAS: クライアントは URL をハードコードしない）
  @property({ type: String, attribute: 'api-url' }) apiUrl = '';
  @property({ type: String, attribute: 'ws-url' }) wsUrl = '';
  @property({ type: Boolean }) readonly = false;

  // コンポーネント内部状態
  @state() private data: SomeType | null = null;

  // Shadow DOM スタイル
  static styles = css`...`;

  // ライフサイクル
  connectedCallback() { super.connectedCallback(); this.load(); }
  disconnectedCallback() { super.disconnectedCallback(); this.cleanup(); }

  private async load() {
    // サーバーから受け取った URL を使う
    this.data = await api.get(this.apiUrl);
  }
}
```

### Lit への URL・権限注入（HATEOAS 原則）

Lit コンポーネントは API パスをハードコードしない。サーバー（Templ テンプレート）が URL と権限を HTML 属性で注入する。

```go
// ✅ サーバーが URL と権限を提供
templ DocumentEditor(doc domain.Document, perms Permissions) {
    <app-doc-editor
        api-url={ fmt.Sprintf("/api/v1/documents/%s", doc.ID) }
        ws-url={ fmt.Sprintf("/ws/documents/%s", doc.ID) }
        readonly?={ !perms.CanEdit }>
    </app-doc-editor>
}
```

この方式の利点:
- URL の変更がサーバー側だけで完結する
- 権限はサーバーが判定し、`readonly` 等の属性で Lit に伝える（HATEOAS: サーバーが操作可否を制御）
- Lit は「サーバーに渡された URL」にアクセスするだけで、ルーティング知識を持たない

### 特徴的パターン

- **自動保存**: 編集後一定時間（2-3秒）の無操作で自動保存
- **読み取り専用モード**: 全エディタが `readonly` プロパティで切替可能
- **Shadow DOM**: スタイルのカプセル化。外部 CSS の影響を受けない
- **イベント通信**: コンポーネント間は CustomEvent で疎結合に通信
- **自己完結**: 各 Lit コンポーネントは `connectedCallback` でサーバーから注入された URL を使いデータを取得し、内部で状態管理する

## エラーハンドリング

サーバーがUI制御する原則はエラーにも適用する。

### HTMX — サーバーがエラー UI も HTML で返す

**バリデーションエラー（422）:**

フォームをエラーメッセージ付きで再レンダリングして返す。クライアント側バリデーション JS は書かない。

```go
func (h *TaskHandler) Create(c *gin.Context) {
    var input CreateTaskInput
    if err := c.ShouldBind(&input); err != nil {
        c.Status(422)
        molecules.TaskForm(input, extractErrors(err)).Render(ctx, c.Writer)
        return
    }
    // ...
}
```

**ビジネスエラー:**

OOB スワップでトースト通知を表示する。

```go
c.Status(403)
// メインレスポンス: 空（または現状維持の HTML）
// OOB: エラートースト
atoms.Toast("error", "権限がありません").Render(ctx, c.Writer)
```

**`response-targets` 拡張によるエラー表示先の分離:**

```html
<form hx-post="/tasks"
      hx-target="#task-list"
      hx-target-422="#form-errors"
      hx-target-5*="#global-error">
  ...
  <div id="form-errors"></div>
</form>
```

**ネットワーク障害・予期しない 5xx:**

唯一クライアント側で処理する。グローバルリスナーで汎用トーストを表示。

```javascript
document.body.addEventListener('htmx:responseError', (e) => {
  showToast('error', '通信エラーが発生しました。再試行してください。');
});
```

### Lit — コンポーネント内で自己完結

Lit は JSON API を使うため、自前で try/catch してコンポーネント内にエラー状態をレンダリングする。

```typescript
private async load() {
  try {
    // サーバーから注入された URL を使う（HATEOAS: URL をハードコードしない）
    this.data = await api.get(this.apiUrl);
    this.error = null;
  } catch (e) {
    this.error = e instanceof ApiError ? e.message : '読み込みに失敗しました';
  }
}
```

### Huma API — OpenAPI 準拠のエラーレスポンス

Huma のバリデーションエラーは自動的に RFC 7807 Problem Details 形式で返る。カスタムエラーも同形式に統一する。

## API クライアント（lib/api.ts）

```typescript
// CSRF トークンを meta タグから自動取得
// credentials: 'same-origin' で Cookie 送信
// レスポンスは JSON 自動パース

get<T>(path: string): Promise<T>
post<T>(path: string, body?): Promise<T>
put<T>(path: string, body?): Promise<T>
patch<T>(path: string, body?): Promise<T>
del<T>(path: string): Promise<T>
uploadFile<T>(path: string, file: File): Promise<T>
```

Lit コンポーネントは必ず `lib/api.ts` を経由して API を呼ぶ。直接 `fetch()` を使わない。

## WebSocket（lib/ws.ts）

- 自動再接続（指数バックオフ、最大10回リトライ）
- JSON メッセージのパース
- `onOpen`, `onMessage`, `onClose` コールバック

Lit コンポーネントは必ず `lib/ws.ts` を経由して WebSocket を使う。直接 `new WebSocket()` を使わない。

## セキュリティ

- CSRF トークン: meta タグから取得し全リクエストに付与
- 認証: Cookie ベースのセッション（SSR）+ Bearer トークン / API キー（API）
- 読み取り専用モード: 権限に応じてエディタを readonly で描画

## スタイリング方針

| 対象 | 手法 |
|------|------|
| Templ テンプレート | Tailwind CSS ユーティリティクラス |
| Lit Web Components | Shadow DOM 内の css テンプレートリテラル |
| ダークモード | CSS カスタム変数 + Tailwind のダークモード |

## テスト戦略

レイヤーごとにテスト手法を使い分ける。HTMX インタラクションは E2E でカバーする。

| レイヤー | テスト手法 | 検証内容 |
|---------|----------|---------|
| Go ハンドラ | `httptest` + HTML アサーション | 正しい HTML フラグメント/フルページが返るか、ステータスコード |
| Templ テンプレート | Go テストで `Render()` → HTML 文字列アサーション | コンポーネント出力が期待通りか |
| Lit コンポーネント | `@open-wc/testing` + `@web/test-runner` | コンポーネント単体の振る舞い |
| E2E | Playwright | HTMX インタラクション含むユーザーフロー全体 |

**Go ハンドラテストの例:**

```go
func TestTaskList_HTMXRequest(t *testing.T) {
    req := httptest.NewRequest("GET", "/tasks", nil)
    req.Header.Set("HX-Request", "true")
    w := httptest.NewRecorder()

    handler.List(createContext(w, req))

    assert.Equal(t, 200, w.Code)
    assert.NotContains(t, w.Body.String(), "<html>")  // フラグメント = <html> なし
    assert.Contains(t, w.Body.String(), "task-list")
}
```

## Huma API パターン

Huma で登録する JSON API には適切な Input/Output 構造体を定義する。

### HATEOAS と JSON API の位置付け

HALT における HATEOAS の主戦場は HTMX（HTML レスポンス）であり、JSON API ではない。JSON API に `_links` 等のハイパーメディアリンクは含めない（ミニマリズム優先）。

代わりに、Huma が自動生成する **OpenAPI 3.1 スペック**（`/api/v1/openapi.json`）が API の発見メカニズムとして機能する。Lit コンポーネントはサーバーから HTML 属性で注入された URL を使うため、クライアント側で URL をハードコードする必要はない。

```go
type CreateTaskInput struct {
    Body struct {
        Title       string `json:"title" required:"true" minLength:"1" maxLength:"200" doc:"タスクタイトル"`
        Description string `json:"description" maxLength:"5000" doc:"タスク説明"`
        ProjectID   string `json:"project_id" required:"true" doc:"所属プロジェクトID"`
    }
}

type CreateTaskOutput struct {
    Body domain.Task
}

huma.Register(api, huma.Operation{
    Method:  http.MethodPost,
    Path:    "/api/v1/tasks",
    Summary: "タスク作成",
}, func(ctx context.Context, input *CreateTaskInput) (*CreateTaskOutput, error) {
    task, err := svc.CreateTask(ctx, input.Body.Title, input.Body.Description, input.Body.ProjectID)
    if err != nil {
        return nil, huma.Error400BadRequest("タスク作成に失敗しました", err)
    }
    return &CreateTaskOutput{Body: *task}, nil
})
```

- Input 構造体にバリデーションタグ（`required`, `minLength`, `maxLength` 等）を設定
- Output 構造体の `Body` フィールドに domain モデルを使用（SSR ハンドラと同じデータソース）
- `doc` タグで OpenAPI ドキュメントを充実させる

## ビルドスクリプト

```json
{
  "build": "npm run build:css && npm run build:js && npm run copy:htmx",
  "build:js": "node esbuild.config.mjs",
  "build:css": "npx @tailwindcss/cli -i src/css/app.css -o dist/css/app.css --minify",
  "copy:htmx": "cp node_modules/htmx.org/dist/htmx.min.js dist/js/",
  "dev": "concurrently \"npm run dev:css\" \"npm run dev:js\""
}
```

**esbuild 設定**:
- エントリーポイント: 各 Web Component ごと
- 出力: ES モジュール形式
- 本番: minify 有効、開発: sourcemap 有効

**静的ファイル配信**:
- Gin の `Static("/dist", "./static/dist")` で配信
- 開発: `Cache-Control: no-cache`
- 本番: `Cache-Control: public, max-age=31536000`（デプロイ時にファイル更新で対応。ハッシュ付与はしない — シンプル優先）
- Templ テンプレートの `<script>` タグには `type="module"` を付ける（ES モジュール形式）

## 開発ワークフロー

3プロセスを並行実行する。`Makefile` の `dev` ターゲットで一発起動。

```makefile
.PHONY: dev
dev:
	@echo "Starting development servers..."
	@concurrently \
		"air" \
		"templ generate --watch" \
		"npm run dev --prefix static"
```

| プロセス | ツール | 役割 |
|---------|-------|------|
| Go サーバー | air | Go ファイル変更時のホットリロード |
| Templ 生成 | `templ generate --watch` | `.templ` 変更時に `_templ.go` を再生成 |
| フロントエンドビルド | `npm run dev` | CSS/JS のウォッチビルド |

**開発フロー:**
1. `.templ` を編集 → `templ generate --watch` が `_templ.go` を生成 → `air` が検知してサーバー再起動
2. `.ts` を編集 → esbuild がバンドル → ブラウザリロードで反映
3. `.css` を編集 → Tailwind がビルド → ブラウザリロードで反映
