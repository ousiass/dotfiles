# Shopify Section Schema 早見表

Phase 4で `{% schema %}` を生成する際のsetting types / block types / presets のリファレンス。

## Input setting types

### テキスト系

| type | 用途 | 例 |
|------|------|---|
| `text` | 1行テキスト | 見出し、ボタンラベル、キャッチコピー |
| `textarea` | 複数行プレーンテキスト | 説明文（装飾なし） |
| `richtext` | 装飾可HTML（段落・リンク・太字） | 本文、利用規約 |
| `inline_richtext` | インライン装飾（強調・リンクのみ、ブロック要素なし） | 1行装飾テキスト |
| `html` | 生HTML（危険、管理者のみ編集） | 埋め込みコード |
| `liquid` | Liquidコード | カスタム処理 |
| `number` | 数値 | 表示件数、列数 |
| `range` | スライダー数値（min/max/step必須） | 幅、余白、不透明度 |
| `checkbox` | 真偽値 | 表示/非表示トグル |
| `radio` | 単一選択（2〜4個） | 配置（左/中央/右） |
| `select` | 単一選択（多数） | サイズ、スタイル |

### メディア系

| type | 用途 | Liquidでの取り出し |
|------|------|-------------------|
| `image_picker` | 画像 | `{{ section.settings.image \| image_url: width: 800 \| image_tag }}` |
| `video` | Shopify上の動画 | `{{ section.settings.video \| video_tag: autoplay: true }}` |
| `video_url` | YouTube/Vimeo URL | `{{ section.settings.video_url }}` |
| `font_picker` | フォント | `{{ settings.font_heading.family }}, {{ settings.font_heading.fallback_families }}` |

### 色系

| type | 用途 |
|------|------|
| `color` | 単色 |
| `color_background` | グラデーションOK |
| `color_scheme` | カラースキーム（theme全体設定と連動） |
| `color_scheme_group` | カラースキーム定義（theme settingsのみ） |

### リンク/リソース系

| type | 用途 | Liquid |
|------|------|--------|
| `url` | 任意URL（内部・外部） | `{{ section.settings.link }}` |
| `link_list` | メニュー | `{% for link in linklists[section.settings.menu].links %}` |
| `article` | 記事1つ | `{{ articles[section.settings.article] }}` |
| `blog` | ブログ1つ | `{{ blogs[section.settings.blog] }}` |
| `collection` | コレクション1つ | `{{ collections[section.settings.collection] }}` |
| `collection_list` | コレクション複数 | `{% for c in section.settings.collections %}` |
| `page` | ページ1つ | `{{ pages[section.settings.page] }}` |
| `product` | 商品1つ | `{{ all_products[section.settings.product] }}` |
| `product_list` | 商品複数 | `{% for p in section.settings.products %}` |
| `metaobject` | メタオブジェクト | `{{ section.settings.metaobject }}` |
| `metaobject_list` | メタオブジェクト複数 | `{% for m in section.settings.metaobjects %}` |

### UI構造系（設定画面のグルーピング）

| type | 用途 |
|------|------|
| `header` | 設定画面のグループ見出し（値なし、`content` のみ） |
| `paragraph` | 補足説明（値なし、`content` のみ） |

## Setting の基本構造

```json
{
  "type": "text",
  "id": "heading",
  "label": "見出し",
  "default": "ようこそ",
  "info": "30文字以内推奨"
}
```

- `id` はsection内で一意、小文字スネークケース
- `label` はテーマエディタに表示される管理者向け日本語
- `default` は任意。画像系は省略（デフォルト画像はassets/の参照で別途）
- `info` はヘルプテキスト。長くなるならpresetsの工夫で補う

### range固有

```json
{ "type": "range", "id": "padding_top", "min": 0, "max": 100, "step": 4, "unit": "px", "default": 40, "label": "上余白" }
```

### select/radio固有

```json
{ "type": "select", "id": "alignment", "options": [
    { "value": "left", "label": "左" },
    { "value": "center", "label": "中央" }
  ], "default": "center", "label": "配置" }
```

## Blocks

繰り返し要素（商品カード、FAQ項目、特徴、お客様の声等）はblocks化。

```json
{
  "blocks": [
    {
      "type": "feature",
      "name": "特徴",
      "settings": [
        { "type": "image_picker", "id": "icon", "label": "アイコン" },
        { "type": "text", "id": "title", "label": "タイトル" },
        { "type": "textarea", "id": "body", "label": "説明" }
      ]
    }
  ],
  "max_blocks": 12
}
```

- `type` はsection内でユニーク、英小文字スネーク
- 異なる種類のblockを並列で持てる（例: `image` block と `text` block を交互）
- `max_blocks` は必要時のみ（デフォルト16、最大50）

### section本体でのblock描画

```liquid
{% for block in section.blocks %}
  {% case block.type %}
    {% when 'feature' %}
      {% render 'molecules/feature-card',
        icon: block.settings.icon,
        title: block.settings.title,
        body: block.settings.body %}
  {% endcase %}
{% endfor %}
```

## Presets

テーマエディタの「セクションを追加」から選べるようにする。

```json
{
  "presets": [
    {
      "name": "特徴リスト",
      "category": "コンテンツ",
      "settings": { "heading": "選ばれる理由" },
      "blocks": [
        { "type": "feature" },
        { "type": "feature" },
        { "type": "feature" }
      ]
    }
  ]
}
```

- `name` はセクション追加ダイアログの表示名
- `category` で分類（「コンテンツ」「画像とテキスト」等）
- `settings`, `blocks` は初期状態
- main-*.liquid（templates/*.json専用）には `presets` は**不要**
- 汎用sectionには必ず入れる

## Enabled on / Disabled on

sectionが配置できるテンプレートを制限。

```json
{
  "enabled_on": { "templates": ["index", "collection"] }
}
```

または

```json
{
  "disabled_on": { "templates": ["cart", "checkout"] }
}
```

`groups`（header/footer/aside）指定も可能：`{ "groups": ["header"] }`

## 完全なschemaテンプレート

```liquid
{% schema %}
{
  "name": "特徴セクション",
  "tag": "section",
  "class": "section",
  "settings": [
    { "type": "text", "id": "heading", "label": "見出し", "default": "選ばれる理由" },
    { "type": "richtext", "id": "description", "label": "説明" },
    { "type": "image_picker", "id": "background", "label": "背景画像" },
    { "type": "header", "content": "レイアウト" },
    { "type": "range", "id": "padding_top", "min": 0, "max": 100, "step": 4, "unit": "px", "default": 40, "label": "上余白" },
    { "type": "range", "id": "padding_bottom", "min": 0, "max": 100, "step": 4, "unit": "px", "default": 40, "label": "下余白" }
  ],
  "blocks": [
    {
      "type": "feature",
      "name": "特徴",
      "settings": [
        { "type": "image_picker", "id": "icon", "label": "アイコン" },
        { "type": "text", "id": "title", "label": "タイトル", "default": "特徴タイトル" },
        { "type": "textarea", "id": "body", "label": "説明" }
      ]
    }
  ],
  "max_blocks": 12,
  "presets": [
    {
      "name": "特徴リスト",
      "category": "コンテンツ",
      "blocks": [{ "type": "feature" }, { "type": "feature" }, { "type": "feature" }]
    }
  ]
}
{% endschema %}
```

## templates/*.json の構造

main-* セクションを1つ置くだけの薄いラッパー：

```json
{
  "sections": {
    "main": {
      "type": "main-product",
      "settings": {}
    }
  },
  "order": ["main"]
}
```

複数sectionを並べる場合：

```json
{
  "sections": {
    "main": { "type": "main-index", "settings": {} },
    "features": { "type": "features", "settings": {} },
    "cta": { "type": "cta", "settings": {} }
  },
  "order": ["main", "features", "cta"]
}
```

代替テンプレート（`page.about.json` 等）も同じ構造。ファイル名末尾がテーマエディタで選択肢になる。

## よくある落とし穴

- `settings_data.json` を空 `{}` にすると Shopify CLI が怒る → `{"current": {}}` が正
- `image_picker` の default は指定不可（画像IDを埋め込めないため）
- `id` の重複は静かに後勝ちになる → schema作成時に重複チェック
- `article`/`blog`/`product` 型はストアに該当データが無いと描画で null になる → `{% if %}` で防御
- richtextのdefault値は `"<p>...</p>"` のようにタグ付きで指定（プレーンテキストだと警告）
- schema末尾のカンマはJSONパースエラー → 手書きで追加する時は注意
