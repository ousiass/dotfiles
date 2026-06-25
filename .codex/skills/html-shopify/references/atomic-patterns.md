# Atomic Design 分類パターン

Phase 3でHTMLからatoms/molecules/organismsを抽出する際の判定基準。
Tailwindクラス署名とDOM構造から分類する。

## 判定フロー

1. その要素は**単一の意味単位**か？
   - はい → atom候補へ
   - いいえ → 2へ
2. **2〜3のatomを束ねた特定機能**を担うか？
   - はい → molecule候補へ
   - いいえ → 3へ
3. **sectionサイズの独立した構造**（ページ内で自己完結）か？
   - はい → organism候補へ
   - いいえ → section内にインラインのまま残す（共通化しない）

## Atoms 早見表

| 名前 | Tailwindクラス署名の例 | DOM |
|------|----------------------|-----|
| `button-primary` | `bg-blue-* text-white rounded px-* py-*` | `<button>` or `<a>` |
| `button-secondary` | `border text-blue-* rounded px-* py-*` | `<button>` or `<a>` |
| `button-ghost` | `text-* hover:bg-* rounded` | `<button>` or `<a>` |
| `heading-page` | `text-3xl\|4xl font-bold` | `<h1>` |
| `heading-section` | `text-2xl font-bold` | `<h2>` |
| `heading-sub` | `text-xl font-semibold` | `<h3>` |
| `input-text` | `border rounded px-3 py-2 focus:ring-*` | `<input type="text\|email\|tel">` |
| `textarea` | `border rounded px-3 py-2 resize-y` | `<textarea>` |
| `select` | `border rounded px-3 py-2 appearance-none` | `<select>` |
| `icon` | `w-* h-* fill-* stroke-*` | `<svg>` |
| `badge` | `inline-flex items-center rounded-full bg-* text-xs px-* py-*` | `<span>` |
| `tag` | `inline-block border rounded px-2 py-0.5 text-xs` | `<span>` or `<a>` |
| `label` | `block text-sm font-medium text-gray-*` | `<label>` |
| `price` | `text-* font-*`（通貨記号+数字のみ） | `<span>` |
| `link` | `text-blue-* underline hover:*` | `<a>`（単独、ボタン様式でない） |
| `image` | `w-* h-* object-*`（単体画像） | `<img>` |
| `divider` | `border-t border-gray-*` | `<hr>` or `<div>` |

**atomルール**:
- ロジック無し（条件分岐は variant パラメータで切り替えるのみ）
- 他のatom/moleculeを呼ばない（`{% render %}` 禁止）
- 受け取るプロパティは3つまで推奨（label, variant, href 等）

## Molecules 早見表

| 名前 | 構成 | 典型DOM |
|------|------|--------|
| `form-field` | label + input + error-text | `<div>label + input + <p class="text-red-*">` |
| `search-bar` | input + icon + button | `<form>` または `<div class="flex">` |
| `product-card` | image + heading-sub + price + button | `<div>`（画像→情報縦並び） |
| `article-card` | image + heading-sub + excerpt + link | `<article>` or `<div>` |
| `nav-item` | icon + text (+ badge) | `<a class="flex items-center">` |
| `breadcrumb` | link + divider + link ... | `<nav>` or `<ol>` |
| `dropdown` | button + list | `<div class="relative">` |
| `tab-item` | icon? + label + underline | `<button>` |
| `stat-card` | heading + 数値 + 補足 | `<div>` 3要素縦並び |
| `list-item-with-icon` | icon + heading + text | `<li>` or `<div>` |
| `price-with-discount` | price-regular + price-sale + badge | `<div class="flex items-center gap-*">` |
| `rating` | star-icons × N + 数値 | `<div class="flex">` |
| `alert` | icon + heading + text | `<div role="alert">` |

**moleculeルール**:
- 2〜3種類のatomを組み合わせる
- 自分自身は小さなロジック（variant, state）を持ってよい
- organism/sectionから `{% render %}` で呼ばれる
- molecule→moleculeの参照は避ける（深さ1までに留める）

## Organisms 早見表

| 名前 | 構成 |
|------|------|
| `site-header` | logo + nav (molecule複数) + search-bar + cart-icon |
| `site-footer` | logo + nav-columns + SNS-icons + copyright |
| `hero` | heading-page + text + button + background-image |
| `product-grid` | product-card × N（グリッド/フレックス） |
| `article-list` | article-card × N |
| `feature-list` | list-item-with-icon × N |
| `testimonials` | testimonial-card × N |
| `cta-section` | heading + text + button（大きめの帯） |
| `pricing-table` | price-card × N |
| `faq-list` | accordion-item × N |
| `contact-form` | form-field × N + button |
| `newsletter` | heading + form-field + button |
| `breadcrumb-bar` | breadcrumb（コンテナ付き） |
| `main-product` | image-gallery + product-info + add-to-cart（商品詳細専用） |
| `cart-items` | line-item × N + summary |

**organismルール**:
- sectionから呼ばれる単位
- section自体を organism にする選択肢もある（site-header.liquid は section と snippets の両方を作らず、section内で直接マークアップ）
- 商品/コレクション系のorganismはLiquidループ（`{% for product in collection.products %}`）を含む

## 汎用HTMLの注意パターン

- **インラインSVG**: 同一SVG（lucide, heroicons, feather等）が複数箇所に出たら `atoms/icon-{name}.liquid` に切り出す
- **aria属性**: 元HTMLの aria-label / role / aria-expanded は保持する（アクセシビリティのため削らない）
- **ダミーテキストの繰り返し**: Lorem系が3回以上出てきたら loop化を検討（blocks or dummy_count setting）
- **画像URLのプレースホルダー**: `picsum.photos` / `placehold.co` / `unsplash.com` 等は image_picker化。デフォルト値としてのURLは置かず、`{% if section.settings.image %}...{% endif %}` で未設定時フォールバック
- **Font**: `<link rel="stylesheet" href="https://fonts.googleapis.com/...">` があれば theme.liquid の共通headに移す
- **scriptタグ**: 外部CDN（alpine, htmx等）の`<script>`は theme.liquid の共通headに移す。インラインスクリプトは該当section内に残す
- **既存CSSファイル**: Tailwind CDN化するので元のCSSリンクは削除。ただし Tailwind では表現できない独自スタイルは`<style>`として該当sectionに残す

## 分類で迷ったときの原則

- **再利用されないなら切り出さない**: 1回しか出てこない塊をmoleculeにすると保守コストの方が高い
- **名前が付けづらいなら単位が悪い**: `card-with-image-and-text-and-button` のような冗長な名前になるなら、もう一段粒度を上げる（例: `article-card`）か下げる（atomsで組む）
- **atomが薄すぎるのはOK**: 4行のliquidでもatom化する価値はある（variantの一元管理に効く）
