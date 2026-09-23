# ビルド・設定チェック

## チェック対象

- `package.json` — npm スクリプト
- `esbuild.config.*` — esbuild 設定
- `tailwind.config.*` — Tailwind CSS 設定
- `dist/` — ビルド成果物

## チェック項目

### 1. esbuild エントリーポイント設定（🟠 Important）

各 Web Component が個別のエントリーポイントとしてバンドルされているか確認する。

検出方法:
1. `esbuild.config.*` を読み込み、`entryPoints` を確認
2. `src/components/` 内の各コンポーネントディレクトリに対応するエントリーがあるか照合
3. 全コンポーネントを1ファイルにバンドルしていないか確認（コンポーネント単位の遅延読み込みを阻害する）

### 2. HTMX のコピー設定（🟡 Suggestion）

`node_modules/htmx.org/dist/htmx.min.js` が `dist/js/` にコピーされる設定があるか確認する。

検出方法:
1. `package.json` の `scripts` に `copy:htmx` または同等のコマンドがあるか
2. `htmx.min.js` のパスがテンプレートの `<script>` タグと一致するか

### 3. Tailwind CSS ビルド設定（🟡 Suggestion）

Tailwind CSS のビルドが正しく設定されているか確認する。

チェックポイント:
- エントリーポイント（`src/css/app.css`）が存在するか
- `content` に `.templ` ファイルが含まれているか（Templ テンプレート内のクラスを検出するため）
- 出力先（`dist/css/app.css`）がテンプレートの `<link>` タグと一致するか

### 4. 開発/本番ビルドの分離（🟢 Minor）

開発ビルドと本番ビルドが適切に分離されているか確認する。

チェックポイント:
- 開発: `sourcemap` 有効、`minify` 無効
- 本番: `minify` 有効
- `dev` スクリプトが CSS と JS のウォッチを並行実行するか
