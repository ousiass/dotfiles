# クロスレイヤー整合性チェック

## チェック対象

- Templ テンプレート内のカスタム要素タグと属性
- Lit コンポーネントの `@property()` 定義
- テンプレート内の `<script>` / `<link>` タグ
- `dist/` ディレクトリのビルド成果物
- `.templ` ファイルと `_templ.go` 生成ファイル

## チェック項目

### 1. Templ ↔ Lit 属性バインディング不一致（🔴 Critical）

Templ テンプレートがカスタム要素に渡す HTML 属性と、Lit コンポーネントの `@property()` が対応しているか確認する。

検出方法:
1. `.templ` ファイルからカスタム要素タグ（`<app-prefix-*>`）を検出し、渡されている属性を列挙
   - 例: `<app-doc-editor entity-id={id} readonly={!canEdit}>`
2. 対応する Lit コンポーネントの `@property()` 定義を取得
3. 以下の不一致を検出:
   - テンプレートが渡す属性に対応する `@property()` がない → 🔴 Critical（属性が無視される）
   - `@property()` の型と渡される値の型が不一致（例: `type: Number` なのに文字列を渡す）→ 🔴 Critical
   - Lit 側の必須プロパティ（デフォルト値なし）にテンプレートから値が渡されていない → 🟠 Important

注意:
- HTML 属性名はケバブケース（`entity-id`）、Lit プロパティはキャメルケース（`entityId`）。自動変換を考慮する
- `@property({ attribute: 'custom-name' })` のカスタム属性名マッピングも確認する

### 2. 静的アセットパスの不一致（🔴 Critical）

テンプレートの `<script>` / `<link>` タグが参照するパスにビルド成果物が存在するか確認する。

検出方法:
1. layout テンプレートおよび pages テンプレートから `<script src="...">` と `<link href="...">` を抽出
2. `dist/` ディレクトリの実際のファイル一覧と照合
3. 一致しないパスを報告

チェックポイント:
- Web Component の JS バンドルパスが正しいか（`/dist/js/{component}.js`）
- `htmx.min.js` のパスが正しいか
- Tailwind CSS のパスが正しいか（`/dist/css/app.css`）
- `<script>` タグに `type="module"` が付いているか（ES モジュール形式のバンドルに必要）

### 3. Templ 生成ファイルの鮮度（🟠 Important）

`.templ` ファイルの最終更新日時と対応する `_templ.go` ファイルの最終更新日時を比較する。

検出方法:
1. `.templ` ファイルを列挙
2. 同ディレクトリの `_templ.go` ファイルとペアリング
3. `.templ` が `_templ.go` より新しい場合、再生成が必要として報告
4. `.templ` は存在するが `_templ.go` が存在しない場合も報告

### 4. WebSocket lib 未使用（🟠 Important）

Lit コンポーネントが `lib/ws.ts` を使わず生の `WebSocket` コンストラクタを直接使っていないか確認する。

検出方法:
1. `.ts` ファイル内の `new WebSocket(` を検索
2. `lib/ws.ts` 自身を除外
3. `lib/ws.ts` の import なしに WebSocket を使っているファイルを報告

直接 `WebSocket` を使うと自動再接続や指数バックオフの恩恵を受けられない。
