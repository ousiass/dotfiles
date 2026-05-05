---
name: spec-to-hugo
description: 既存の仕様書ディレクトリをHextraテーマのHugo仕様書サイトに変換する
---

# spec-to-hugo

既存の `spec/` や `docs/` 配下にあるMarkdown仕様書を、Hextraテーマを使ったHugoドキュメントサイトとして公開できるよう構成する。

## 前提条件

- Hugo がインストール済み（`hugo version` で確認）
- Go がインストール済み（Hugo Modules に必要）
- 仕様書が `spec/` または `docs/` 配下にMarkdownで存在する

## ワークフロー

### Step 1: 仕様書ディレクトリの特定

プロジェクトルートから仕様書を探す:

```
spec/**/*.md
docs/**/*.md
```

見つかったディレクトリ構造をユーザーに確認する。

### Step 2: Hugo サイトの初期化

仕様書のあるディレクトリ（例: `spec/`）をHugoサイトのルートとして構成する。

**生成するファイル一覧:**

| ファイル | 説明 |
|---------|------|
| `hugo.toml` | サイト設定（Hextraテーマ、日本語設定） |
| `go.mod` | Hugo Modules 定義 |
| `go.sum` | モジュールチェックサム |
| `netlify.toml` | Netlifyデプロイ設定（Edge Function 経由で Basic 認証） |
| `wrangler.jsonc` | Cloudflare Workers + Static Assetsデプロイ設定 |
| `worker.js` | Cloudflare Worker エントリ（Basic 認証 → ASSETS 配信） |
| `netlify/edge-functions/auth.ts` | Netlify Edge Function（Basic 認証） |
| `Makefile` | ビルド・開発用コマンド |
| `package.json` | Markdown lint/format ツール |
| `.markdownlint-cli2.jsonc` | markdownlint設定（日本語ドキュメント向け） |
| `.prettierrc` | Prettier設定（必要なら） |
| `layouts/partials/custom/head-end.html` | Mermaid図ズーム機能 |
| `layouts/shortcodes/pdf.html` | PDF埋め込みショートコード |
| `content/_index.md` | トップページ（docsへリダイレクト） |
| `content/docs/_index.md` | ドキュメントセクション定義 |

### Step 3: コンテンツ構造の変換

既存のMarkdownファイルを `content/docs/` 配下に配置する。

#### 3a. ディレクトリマッピング

既存の仕様書ディレクトリ構造に応じてマッピングする:

**パターン A: フラット構造**（ファイルが1ディレクトリに並んでいる場合）
```
spec/                          content/docs/spec/
├── 01-background.md    →     ├── 01-background.md
├── 02-scope.md         →     ├── 02-scope.md
└── ...                        └── _index.md（新規作成）
```

**パターン B: 階層構造**（サブディレクトリがある場合）
```
docs/                          content/docs/
├── requirements/       →     ├── requirements/
│   ├── functional.md          │   ├── functional.md
│   └── ...                    │   └── _index.md（新規作成）
├── architecture/       →     ├── architecture/
│   └── ...                    │   └── _index.md（新規作成）
└── ...                        └── _index.md
```

#### 3b. Frontmatter の付与・調整

既存ファイルにfrontmatterがない場合、追加する:

```yaml
---
title: "ファイル名または最初のH1見出しから推定"
weight: N  # ファイル番号プレフィクスから推定、なければ配置順
description: "最初の段落から要約"
---
```

既存のfrontmatterがある場合は `weight` だけ追加（なければ）。

#### 3c. セクションインデックス

各ディレクトリに `_index.md` を作成:

```yaml
---
title: "セクション名"
weight: N
sidebar:
  open: true
---

セクションの概要（1〜2行）。
```

### Step 4: hugo.toml と wrangler.jsonc の設定

テンプレートを元に、以下をユーザーに確認して設定:

- **title**: サイトタイトル（例: 「○○システム 仕様書」）
- **params.description**: サイトの説明文
- メニュー項目の最初のリダイレクト先
- **wrangler.jsonc の `name`**: Workers のプロジェクト名。サイトタイトルから kebab-case 英数字に変換（例: 「○○システム 仕様書」→ `marumaru-system-docs`）。`compatibility_date` は本日の日付（YYYY-MM-DD）に更新

`templates/hugo.toml.tmpl` と `templates/wrangler.jsonc.tmpl` を参照して生成する。

### Step 5: レイアウト・静的ファイルの配置

`templates/` ディレクトリから以下をコピー:

- `layouts/partials/custom/head-end.html` — Mermaid図クリックズーム
- `layouts/shortcodes/pdf.html` — PDF埋め込み
- `static/` ディレクトリ作成（PDFなどの静的アセット用）

### Step 5b: Basic 認証スクリプトの配置

両プラットフォームとも常に Basic 認証で全パスを保護する。env 未設定時は 503 を返す。

`templates/` から以下を配置（`{{SITE_TITLE}}` を WWW-Authenticate realm に置換）:

- `worker.js` — プロジェクトルートに配置（Cloudflare Worker エントリ）
- `netlify/edge-functions/auth.ts` — `templates/edge-auth.ts.tmpl` をリネームして配置

### Step 6: 開発ツールのセットアップ

1. `go mod init` → `go mod tidy` で Hugo Modules 初期化
2. `npm install` で prettier / markdownlint インストール
3. `make serve` で動作確認を促す

### Step 7: ユーザーへの案内

セットアップ完了後、以下を案内:

```
セットアップ完了！

■ ローカル確認
  make serve  → http://localhost:1313

■ よく使うコマンド
  make build  → 本番用ビルド
  make fmt    → Markdownフォーマット
  make lint   → Markdownリント
  make fix    → フォーマット＋リント修正

■ Netlifyデプロイ
  Netlifyダッシュボードでリポジトリを接続するだけ。
  ビルドコマンドと公開ディレクトリは netlify.toml から自動読み込みされます。
  Site configuration → Environment variables で以下を設定（必須）:
    BASIC_AUTH_USER  = <ユーザー名>
    BASIC_AUTH_PASS  = <パスワード>  (Sensitive variable で登録推奨)
  未設定だと Edge Function が 503 を返してサイトが見られません。

■ Cloudflare Workersデプロイ（Static Assets）
  Cloudflareダッシュボード → Workers & Pages → Create → Import a repository
  ビルドコマンド: hugo --gc --minify
  ビルド出力ディレクトリ: public
  以降のpushで自動デプロイ。assets配信は wrangler.jsonc から読み込まれます。
  プロジェクト Settings → Variables and Secrets で以下を設定（必須）:
    BASIC_AUTH_USER  = <ユーザー名>  (Plaintext または Secret)
    BASIC_AUTH_PASS  = <パスワード>  (Secret 推奨)
  未設定だと Worker が 503 を返してサイトが見られません。
  ※ Cloudflare Pages は Workers + Static Assets に統合されたため非推奨

■ ページの追加
  content/docs/<セクション>/ にMarkdownファイルを追加するだけ。
  frontmatterにtitleとweightを指定してください。
```

## 重要な注意点

- 既存のMarkdownファイルは**移動**ではなく**コピーまたはシンボリックリンク**するか、ユーザーに移動の許可を得る
- go.sumは `hugo mod tidy` で自動生成されるため、テンプレートの値は参考値
- Hextraテーマのバージョンは最新安定版を使う（現時点: v0.12.1）
- `.gitignore` に `public/`, `resources/_gen/`, `.hugo_build.lock`, `node_modules/`, `.wrangler/` を追加

## テンプレートファイル

設定ファイルのテンプレートは `templates/` ディレクトリにある。各ファイル内の `{{PLACEHOLDER}}` をプロジェクトに合わせて置換する。
