---
name: html-shopify
description: 任意のHTMLモック（zip/ディレクトリ/単一ファイル）をShopify OS 2.0テーマ（Atomic Design snippets構造）に変換する
user-invocable: true
---

# HTML Shopify

任意のHTMLモック（Figma export / Webflow export / 手書きHTML / その他ツール出力）をShopify Online Store 2.0のテーマディレクトリに変換する。
snippets階層をAtomic Design（atoms / molecules / organisms）で構造化し、テキストは`section.settings`、画像は`image_picker`に差し替えたカスタマイズ可能なテーマを生成する。

Stitch固有の入力形式に特化した姉妹スキル `stitch-shopify` の汎用版。入力パーサのみ異なり、Phase 3以降の変換ロジックは同等。

## 引数

```
/html-shopify [入力パス] [出力先ディレクトリ(省略時: 入力と同階層の shopify-theme/)]
```

## 前提

- 入力: 以下のいずれも受け付ける
  - **zip**: 任意の構造のHTML一式を固めたもの
  - **ディレクトリ**: HTMLを含むフォルダ
  - **単一HTMLファイル**: 1枚のHTMLを1ページとして扱う
- 出力: `shopify theme dev` / `shopify theme push` でそのまま動作するテーマディレクトリ
- CSS: Tailwind CLIで `assets/base.css` を**事前コンパイル**（CDNは使わない、Shopify公式推奨のasset_url配信）
- HTMLの中身は、Liquid化に必要な箇所以外は極力変更しない
- ユーザー確認なしに既存ファイルを上書きしない

## 出力ディレクトリ構造

```
shopify-theme/
├── assets/
│   ├── base.css                # Tailwind CLIで事前コンパイル（CDN不使用）
│   ├── global.js               # 共通JS（必要なら）
│   └── mock-*.{png,jpg,svg,webp}  # モック画像をimage_pickerのデフォルトとして同梱
├── blocks/                     # OS 2.0 theme blocks（section横断で再利用）
│   └── *.liquid
├── config/
│   ├── settings_schema.json
│   └── settings_data.json
├── layout/
│   └── theme.liquid            # asset_urlでbase.css読込 + 共通head
├── sections/
│   ├── header.liquid
│   ├── footer.liquid
│   └── main-*.liquid           # ページごと（main-index, main-product 等）
├── snippets/
│   ├── atoms/*.liquid          # button, heading, input, icon 等
│   ├── molecules/*.liquid      # form-field, product-card, search-bar 等
│   └── organisms/*.liquid      # hero, product-grid, article-list 等
├── templates/
│   ├── index.json
│   ├── product.json
│   ├── collection.json
│   ├── cart.json
│   ├── page.json
│   ├── blog.json
│   ├── article.json
│   ├── 404.json
│   └── search.json
└── locales/
    └── en.default.json
```

snippetsのサブディレクトリは `{% render 'atoms/button' %}` のようにパス付きで参照する（Shopify CLI 3系以降が対応）。

## ワークフロー

### Phase 1: 入力の正規化

入力形式を自動判定し、「1ページ = 1 HTML」のリストに正規化する。

1. **入力タイプ判定**
   - 引数未指定 → 作業ディレクトリ内の `*.zip` / `*.html` / HTMLを含むサブディレクトリを探索し、候補をAskUserQuestionで確認
   - 引数が `.zip` → 一時ディレクトリに展開
   - 引数がディレクトリ → そのまま使用
   - 引数が `.html` ファイル → そのファイル1枚を1ページ扱い

2. **HTMLファイル収集**
   - 展開/指定ディレクトリから `*.html` / `*.htm` を再帰的に収集（`node_modules/`, `.git/`, `dist/` 等は除外）
   - 0件なら中断して入力パスを再確認
   - assets（css/js/img）の位置を記録しておく（後で `assets/` へコピー）

3. **ページリスト作成**
   収集した各HTMLについて、以下の**候補**を内部で計算（確定はPhase 2でユーザーが行う）：
   - 相対パス（例: `pages/about/index.html`）
   - ファイル名由来の素案（`about`, `product`, `index` 等）
   - `<title>` / `<h1>` の抽出結果

4. **出力先ディレクトリ決定**
   候補: 引数 > 入力と同階層の `shopify-theme/`

### Phase 2: ページ→Shopifyテンプレートのマッピング（ユーザー確認）

**自動推定はしない**。Phase 1で集めたページリストを以下の形式で提示し、ユーザーに1ページずつテンプレート割当を決めてもらう：

```
番号 | 入力HTML                    | <title> / <h1>        | 提案テンプレート
-----|----------------------------|-----------------------|------------------
1    | index.html                 | 〇〇ストア             | (未割当)
2    | pages/product.html         | 商品詳細               | (未割当)
3    | pages/about/index.html     | About                 | (未割当)
...
```

Shopify標準テンプレート（`index`, `product`, `collection`, `cart`, `page`, `blog`, `article`, `404`, `search`）を選択肢として案内し、該当しないページは `page.{slug}` 代替テンプレートにする。

AskUserQuestionを使い、ページ数が多い場合は以下の方針でバッチング：

- **ページ数≦4**: 1問で全件を聞く
- **ページ数>4**: 「まず標準9種に割り当てるものを選ぶ → 残りは page.{slug} でよいか確認」の2段構え

ユーザーが回答したマッピング表を最終提示し、承認を得るまで次に進まない。

#### 欠落テンプレートの確認

Shopify標準9種のうちマッピングされなかったものを列挙し、**AskUserQuestionで各テンプレートごとに対応を選ばせる**：

- **自動雛形生成**: 最小構成のsection（タイトル＋本文のsettingsのみ）を生成
- **追加HTMLを用意**: 処理を中断し、ユーザーが対応HTMLを追加後に再実行
- **今回はスキップ**: テンプレートを作らない

「追加HTMLを用意」が1つでも選ばれたら、その時点で処理を終え「追加分を含めて再実行してください」と案内する。

### Phase 3: Atomic Design分解

全ページのHTMLを横断的にスキャンし、再利用可能な要素を識別する。
**判定基準とTailwindクラス署名の早見表は `references/atomic-patterns.md` を参照**（分類に迷ったら必ず読む）。

**分類基準**：

- **atoms** — 単一要素、最小単位（button, heading, input, textarea, select, icon, badge, label, image）
- **molecules** — atomsを2〜3個束ねた機能単位（form-field, search-bar, product-card, nav-item, breadcrumb）
- **organisms** — moleculesとatomsを組み合わせた独立セクション（site-header, site-footer, hero, product-grid, article-list, cta-section）

**抽出手順**：

1. 全ページを走査し、Tailwindクラスの類似度で同種要素をグループ化（Tailwindでない入力なら DOM構造 + class/id 名の類似度で代替）
2. 2回以上出現するパターンを候補に挙げる（1回きりはsection内にインライン）
3. 候補リストをユーザーに提示：

```
■ atoms 候補
- button-primary   (出現: 23回) - bg-blue-600 text-white rounded
- button-secondary (出現: 8回)  - border text-blue-600
- heading-section  (出現: 12回) - text-2xl font-bold
- input-text       (出現: 15回) - border rounded px-3 py-2
...

■ molecules 候補
- product-card  (出現: 15回) - 画像+商品名+価格+ボタン
- form-field    (出現: 9回)  - label+input+error
...

■ organisms 候補
- site-header  (全ページ)
- site-footer  (全ページ)
- hero         (index, collection)
- product-grid (index, collection)
...
```

ユーザーが粒度を調整（分ける/まとめる/命名変更）。承認されるまで次に進まない。

### Phase 4: Shopifyテーマ生成

出力先ディレクトリが存在する場合は上書き確認を取ってから実行。

#### 4-1. layout/theme.liquid

Shopify Dawnを参考にした標準構造を生成：

```liquid
<!doctype html>
<html lang="{{ request.locale.iso_code }}">
  <head>
    <meta charset="utf-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta name="theme-color" content="">
    <link rel="canonical" href="{{ canonical_url }}">
    <link rel="preconnect" href="https://cdn.shopify.com" crossorigin>
    {%- if settings.favicon != blank -%}
      <link rel="icon" type="image/png" href="{{ settings.favicon | image_url: width: 32, height: 32 }}">
    {%- endif -%}
    <title>{{ page_title }}{% if current_tags %} &ndash; tagged "{{ current_tags | join: ', ' }}"{% endif %}{% if current_page != 1 %} &ndash; Page {{ current_page }}{% endif %}{% unless page_title contains shop.name %} &ndash; {{ shop.name }}{% endunless %}</title>
    {%- if page_description -%}
      <meta name="description" content="{{ page_description | escape }}">
    {%- endif -%}
    {{ 'base.css' | asset_url | stylesheet_tag }}
    {{ content_for_header }}
  </head>
  <body>
    {% section 'header' %}
    <main id="MainContent" role="main">{{ content_for_layout }}</main>
    {% section 'footer' %}
    <script src="{{ 'global.js' | asset_url }}" defer></script>
  </body>
</html>
```

- `{{ content_for_header }}` は**必ず `<head>` 内**に置く（App埋め込み・analytics用）
- 入力HTMLの共通`<head>`（font等のlink）は `preconnect` を残しつつ移植。複数ページで異なる場合はユーザーに選択させる
- 元のCSSファイルリンク（`<link rel="stylesheet">`）は削除
- インラインスクリプト・`<script src>` は section 内の `{% javascript %}` または `assets/*.js` + `script_tag` に移す

#### 4-2. snippets/ の生成

承認済みのatoms/molecules/organismsを個別Liquidファイルに：

- **atoms**: propsのみから描画、ロジック無し
  ```liquid
  {% comment %} atoms/button.liquid
    params: label (string), variant (primary|secondary), href (string, optional)
  {% endcomment %}
  {% assign variant = variant | default: 'primary' %}
  {% if variant == 'primary' %}
    {% assign classes = 'bg-blue-600 text-white rounded px-4 py-2' %}
  {% else %}
    {% assign classes = 'border text-blue-600 rounded px-4 py-2' %}
  {% endif %}
  {% if href %}
    <a href="{{ href }}" class="{{ classes }}">{{ label }}</a>
  {% else %}
    <button class="{{ classes }}">{{ label }}</button>
  {% endif %}
  ```

- **molecules**: atomsを`{% render %}`で組み立てる
- **organisms**: 通常sectionから呼ばれる想定。sectionのsettings/blocksをプロパティで受け取る

#### 4-3. sections/ の生成

- `header.liquid`, `footer.liquid`: organisms/site-header, site-footer を呼ぶ薄いラッパー。`{% schema %}` 付き
- ページごとに `main-{template}.liquid`（main-index.liquid, main-product.liquid 等）

**setting type / block / presets の構文は `references/shopify-settings.md` を参照**（schema生成時は必ず確認）。

各sectionに`{% schema %}`を付与し、以下を変換：

| 元の要素 | 変換後 | setting type |
|---------|--------|-------------|
| プレーンテキスト（見出し、段落） | `{{ section.settings.xxx }}` | `text` / `textarea` |
| リッチテキスト（リンク含む段落） | `{{ section.settings.xxx }}` | `richtext` |
| 画像 | 下記「画像変換テンプレート」参照 | `image_picker` |
| CTAボタン（テキスト＋URL） | setting 2つ（`cta_label`, `cta_url`） | `text`, `url` |
| リスト状の繰り返し（特徴、実績、FAQ等） | `{% for block in section.blocks %}` | blocks配列で定義 |

schemaのpresetsも1つ入れ、テーマエディタからsection追加できるようにする。

##### 画像変換テンプレート（モック画像をデフォルトに）

元HTMLの`<img src="...">`は以下のパターンに置換：

```liquid
{%- assign img = section.settings.hero_image -%}
{%- if img != blank -%}
  {{ img | image_url: width: 1600 | image_tag:
       loading: 'lazy',
       widths: '400, 600, 800, 1200, 1600',
       sizes: '(min-width: 750px) 50vw, 100vw',
       alt: section.settings.hero_image_alt | default: img.alt }}
{%- else -%}
  <img src="{{ 'mock-hero.jpg' | asset_url }}"
       alt="{{ section.settings.hero_image_alt | default: '' }}"
       loading="lazy" width="1600" height="900">
{%- endif -%}
```

- `image_picker`は`default`を持てない仕様なので、モック画像を `assets/mock-{section}-{slug}.{ext}` として同梱し、`{% if settings.image %}...{% else %}{{ 'mock-*.ext' | asset_url }}{% endif %}` のフォールバックで表示する
- LCP対象（1枚目のhero等）は `loading: 'lazy'` を外し、`fetchpriority: 'high'` と `preload` を検討
- `width` / `height` 属性は元HTMLから取得（CLS対策。取得できない場合はアスペクト比を推定）
- `alt`は別settingで編集可能にする（画像とペアで `image_alt` setting を置く）

##### section-scoped アセット（Shopify標準）

section固有の動的スタイル・スクリプトは `{% stylesheet %}` / `{% javascript %}` で section 内に埋める（DawnのイディオムでTheme Checkも推奨）：

```liquid
{% schema %}{...}{% endschema %}

{% stylesheet %}
  /* Tailwindで表現できないCSS変数・動的背景等のみここに書く */
  .hero--section-{{ section.id }} { --hero-overlay: {{ section.settings.overlay_color }}; }
{% endstylesheet %}

{% javascript %}
  /* section 初期化ロジック。Shopifyが自動でdeferして結合する */
  customElements.define('hero-section', class extends HTMLElement { ... });
{% endjavascript %}
```

- Tailwindユーティリティで表現できるものは `{% stylesheet %}` に書かない（重複になる）
- `{% javascript %}` は `assets/global.js` より**優先**してsection単位で使う（Shopifyが結合＆最適化）

#### 4-4. 商品・コレクションsectionのLiquid化

`main-product.liquid` / `main-collection.liquid` のダミーデータ部分は以下に置換：

- 商品リスト → `{% for product in collection.products %}`
- 商品タイトル → `{{ product.title }}`
- 商品価格 → `{{ product.price | money }}`
- 商品画像 → `{{ product.featured_image | image_url: width: 1200 | image_tag: loading: 'lazy', widths: '300, 600, 900, 1200', sizes: '(min-width: 750px) 33vw, 100vw' }}`
- 商品リンク → `{{ product.url }}`
- 商品説明 → `{{ product.description }}`
- 商品フォーム → `{% form 'product', product %}...{% endform %}`

メイン商品/コレクション領域以外（お客様の声、特徴紹介等）はsettings/blocks化。

#### 4-5. templates/

Shopify OS 2.0 JSON形式。該当する `main-{template}` section を参照：

```json
{
  "sections": {
    "main": { "type": "main-index", "settings": {} }
  },
  "order": ["main"]
}
```

Phase 2で決めた代替テンプレート（例: `page.about.json`）も同様に生成。

#### 4-6. blocks/（theme blocks, OS 2.0）

複数section間で再利用したいorganismは **theme block** として切り出す（OS 2.0の新機能、Dawn 15+が採用）：

- `blocks/product-card.liquid` のようにtop-level `blocks/` ディレクトリに配置
- section schemaの `blocks` 配列に `{"type": "@theme"}` or `{"type": "@app"}` を含めるとテーマエディタから任意のtheme blockを追加可能
- section内 `blocks` でしか使わないものは theme block にしない（section local blockとして残す）

```liquid
{%- comment -%} blocks/product-card.liquid {%- endcomment -%}
<div {{ block.shopify_attributes }}>
  {% render 'molecules/product-card', product: block.settings.product %}
</div>
{% schema %}
{
  "name": "Product card",
  "settings": [
    { "type": "product", "id": "product", "label": "Product" }
  ]
}
{% endschema %}
```

Phase 3のorganism選定時、ユーザーに「このorganismをtheme blockにするか」を確認する。

#### 4-7. config/, locales/, assets/

- `config/settings_schema.json`: `theme_info` と favicon / color scheme 等のグローバル設定
- `config/settings_data.json`: `{"current": {}}`
- `locales/en.default.json`: 画面文言のキーを格納。section内のハードコード文字列は `{{ 'general.xxx' | t }}` に置換可能な箇所を抽出して収録
- `locales/ja.json` など他言語は空の雛形を作成
- `assets/base.css`: Phase 4-8でTailwind CLIが生成
- `assets/global.js`: 共通の`<script>`由来。無ければ空ファイルまたは省略
- `assets/mock-*.{ext}`: **入力に含まれる画像をフラットコピー**し、`mock-{section-slug}-{原ファイル名}` にリネーム（image_pickerフォールバック用）
- 同名衝突時は連番サフィックス（`-2`, `-3`）。参照箇所も合わせて書き換え

#### 4-8. Tailwind CSS コンパイル

出力ディレクトリに対して Tailwind CLI を実行し `assets/base.css` を生成：

```bash
# 事前に一時ファイル作成
cat > /tmp/base-input.css <<'CSS'
@tailwind base;
@tailwind components;
@tailwind utilities;
CSS

# コンパイル実行
npx tailwindcss@latest \
  -i /tmp/base-input.css \
  -o <出力先>/assets/base.css \
  --content '<出力先>/**/*.liquid' \
  --minify
```

- `--content` で生成済Liquidファイルをスキャンし、使用中のクラスだけをバンドル（JIT動作、通常30-80KB）
- `npx` が使えない環境では bun / pnpm dlx で代替。利用可能なパッケージマネージャをユーザーに確認
- 独自のTailwind設定（色・フォント等）が必要な場合は `tailwind.config.js` を出力先に生成（元HTMLの `<script>tailwind.config = {...}</script>` があれば抽出して使用）
- コンパイル失敗時はエラーをそのまま表示し、手動で修正する案内を出す

### Phase 5: 自己チェック

以下の整合性チェックを行い結果を報告：

- 全sectionに `{% schema %}` があるか
- `templates/*.json` の `type` が実在するsectionを指しているか
- `{% render 'xxx/yyy' %}` の参照先snippetが全て存在するか
- snippets間の引数名が渡し側と受け側で一致しているか
- `assets/`, `config/`, `layout/`, `sections/`, `snippets/`, `templates/`, `locales/` が全て存在するか
- `asset_url` が参照するファイルが `assets/` に実在するか
- `assets/base.css` が生成されており空でないか（Tailwind CLIの結果）
- モック画像フォールバックを使うsectionで、該当 `mock-*` ファイルが `assets/` に存在するか
- `theme.liquid` の `<head>` に `{{ content_for_header }}` があるか
- sectionの `{% stylesheet %}` 内に Tailwindユーティリティが書かれていないか（CSS重複検出）
- `<script src="https://cdn...">` などの外部CDN参照が残っていないか
- **`shopify theme check` を実行**（インストールされていれば）。ERROR レベルがあればその場で修正

異常があれば修正してから次フェーズへ。

### Phase 6: Git commit & push（自動）

出力ディレクトリを含むgitリポジトリを検出して自動でcommit/pushする。

1. **リポジトリ判定**: 出力先から `git rev-parse --show-toplevel` を実行
   - **gitリポジトリ内の場合**: そのリポジトリで commit/push
   - **gitリポジトリ外の場合**: AskUserQuestionで以下を選ばせる
     - `git init` して初期コミットを作る（remoteは後で設定）
     - gitステップをスキップ

2. **ステージング**: 出力先ディレクトリのみを対象にする
   ```
   git add <出力先ディレクトリ>
   ```
   他のワーキングツリーの変更は巻き込まない。

3. **コミットメッセージ**: `CLAUDE.md` の規約に従い `<type>: <説明>` 形式
   - 初回生成: `feat: HTMLモックから生成したShopifyテーマを追加`
   - 既存上書き: `update: HTMLモックから生成したShopifyテーマを更新`
   - type は英語、説明は日本語
   - `--no-verify` 禁止。pre-commit/pre-pushが失敗したら原因を調査・修正してから再実行

4. **プッシュ前の確認**: 以下を1画面で提示してユーザーに最終確認：
   ```
   ブランチ: <current-branch>
   リモート: <remote-url>
   コミット: <commit-message>
   変更ファイル数: <N>
   ```
   承認後に `git push` を実行。リモートが未設定なら push はスキップし案内のみ。

5. **現在ブランチがmain/masterの場合は警告**: 新規ブランチ作成を推奨し、AskUserQuestionで
   - 新規ブランチ `html-shopify/<日付>` を切って commit/push
   - そのままmain/masterに commit/push
   を選ばせる。

### Phase 7: 完了案内

1. 出力ディレクトリの `tree` を表示
2. Phase 5 の自己チェック結果と Phase 6 の git 操作結果をサマリ表示
3. 次アクションを案内：
   ```
   cd <出力先>
   shopify theme check     # 静的検査
   shopify theme dev       # ローカルプレビュー
   shopify theme push -u   # 未公開テーマとしてアップロード
   ```

## Liquid 作法（Shopify標準）

Phase 4の全generation phaseで以下を適用：

- **whitespace制御**: Liquidタグが余分な空白を残さないよう、制御フロー系は `{%- ... -%}` を使う
  ```liquid
  {%- if section.settings.image != blank -%}
    ...
  {%- endif -%}
  ```
- **マルチライン`{% liquid %}`**: 3行以上のassign/ifが続くなら `{% liquid %}` でまとめる
  ```liquid
  {%- liquid
    assign variant = block.settings.variant | default: 'primary'
    assign href = block.settings.href
    if variant == 'primary'
      assign classes = 'bg-blue-600 text-white rounded px-4 py-2'
    else
      assign classes = 'border text-blue-600 rounded px-4 py-2'
    endif
  -%}
  ```
- **`blank`/`empty`判定**: 未定義値は `!= blank` で判定（`!= nil` ではない）
- **`default`フィルター**: fallbackは `| default:` を優先（`{% if x %}{{ x }}{% else %}...{% endif %}` より簡潔）
- **翻訳**: ハードコード文字列は避け、`{{ 'section.hero.cta_label' | t }}` と `locales/en.default.json` で管理。ただしユーザー編集前提のテキストは `section.settings` を優先（固定ラベルだけを `locales` へ）
- **schemaの`t:`プレフィックス**: `{% schema %}` 内の `label` / `info` も翻訳可能：`"label": "t:sections.hero.settings.title.label"`
- **`block.shopify_attributes`**: 各blockのルート要素に必ず `{{ block.shopify_attributes }}` を出力（テーマエディタのインスペクタ用）
- **section id**: 複数配置される可能性があるので CSS class にも `section.id` を含める（`hero--{{ section.id }}` 等）
- **App blocks対応**: 各sectionのblocksに `{"type": "@app"}` を入れ、アプリブロック配置を許容
- **アクセシビリティ**: `alt` / `aria-label` / `role` を保持。画像未設定時は `alt=""`（装飾画像扱い）

## ルール

- ユーザー確認を取る箇所（必須）：
  1. 入力パス候補が複数ある場合の選択
  2. ページ→テンプレートのマッピング（自動推定せず全件確認）
  3. 欠落テンプレートの対応（AskUserQuestion）
  4. Atomic Design分解の粒度
  5. 出力先ディレクトリが既存の場合の上書き
  6. 共通headが複数候補ある場合のベース選択
  7. git push 直前の最終確認（ブランチ/リモート/コミット）
  8. main/masterブランチへの直pushを避けるかの確認
- テキストは必ずsettings化する（ハードコードしない）。固定ラベルは `locales/*.json` 経由
- 画像は必ず`image_picker`化する（URLハードコードしない）。モック画像は `assets/mock-*.{ext}` へコピーし `{% if settings.image %}...{% else %}asset_url{% endif %}` で参照
- CSSは Tailwind CLI で `assets/base.css` にコンパイル。**CDN参照禁止**
- section固有の動的CSS/JSは `{% stylesheet %}` / `{% javascript %}` を優先
- atoms同士は相互参照しない（molecules→atoms、organisms→molecules/atomsの一方向のみ）
- 一時展開ディレクトリは処理完了後に削除する
- 「追加HTMLを用意」の選択肢が出たら処理を中断し、追加込みで再実行させる
- git操作では `--no-verify` を使わない。pre-commit/pre-pushフックは必ず通す
- `git add` は出力先ディレクトリに限定し、他の変更を巻き込まない
- リモート未設定なら push はスキップ（エラー停止しない）
