# visual.css コンポーネント早見表

`templates/visual.css` に定義済みのパターン。**新しいページは必ずこの中から選ぶ**。
ここに無い図が必要になったら、まず既存パターンの組み合わせで表現できないか検討し、
どうしても足りない場合だけ `visual.css` の末尾に新しいクラスを追加する（画像化はしない）。

すべてのスライドは `class: visual-deck` を持つ。ダーク背景は `class: visual-deck v-dark`。

## 情報の型 → パターン決定表

**まずこの表で決める。** 迷ったら、伝えたい情報が「並列」「順序」「対比」「量」のどれかを考える。

| 伝えたい情報 | パターン |
| --- | --- |
| 3つの観点で定義する（誰に / 何を / 何が新しい） | `v-audience` |
| 論点を4つに割る | `v-impact-grid` |
| 並列の要素 3〜6個 | `v-detail-grid`（`-four` `-five` `-six`） |
| 比較対象ごとに箇条書きで並べる | `v-usecase-grid` |
| 2項目の対比 | `v-detail-columns` |
| 2案の対比（現状 / 導入後） | `v-duo` |
| 理由を2つ積む | `v-two-stack` |
| 順序のある段階 4つ | `v-process`（アイコン）/ `v-flow-detail`（矢印つき） |
| 処理の流れ 5段 | `v-pipeline` |
| 時間・成長の推移 | `v-timeline` |
| 階層・レイヤー構造 | `v-arch` |
| 中心と周辺の関係 | `v-hub` |
| 既存システムと新規機能の接続 | `v-bridge` |
| 分断・散在している状態 | `v-fragment` |
| 1つの金額を複数へ配分 | `v-split` |
| 主要指標 3つ | `v-metrics` |
| 数値を帯で3つ並べる | `v-event-strip` |
| 項目の一覧 9〜12個 | `v-stream-grid` / `v-feature-inventory` |
| フェーズごとの範囲 | `v-phase-grid` |
| 行×列のデータ | `v-data-table` |
| ○×の機能比較 | `v-matrix` |
| 規模別のプラン | `v-plans` |
| 単一メッセージ・章の転換 | `v-statement`（`v-dark`） |
| 画面遷移・UI の流れ | `v-phones` |
| 会社概要・体制 | `v-company-list` |

**同じパターンを3ページ続けない。** 続くときは、片方を別の型に組み替えられないか検討する。

## 共通の小要素

```html
<div class="v-kicker">What we do</div>          <!-- h2 の上に置く英語の小見出しラベル -->
<h2>ページの主張を1文で書く見出し</h2>
<p class="v-lead">見出しを補うリード文。1〜2行。</p>
<p class="v-note">脚注・補足。ページ下端に置く。</p>
<div class="v-chips"><span>機能名</span><span>連携先</span></div>
```

ダーク背景では `v-lead v-note-dark` / `v-note v-note-dark` を併用する。

### 結論バナー / 補足ボックス

```html
<div class="v-formula-banner">
  <span>Key point</span>
  <strong>そのページの結論を1文で言い切る</strong>
</div>

<div class="v-internal-note">
  <strong>提供価値</strong>
  <span>読み手が気にする論点への回答を短く書く。</span>
</div>
```

## 表紙・章扉・クロージング

```html
<!-- 表紙: 画像は全面、コピーは上に重なる -->
<div class="v-cover">
  <img src="/img/visual/cover.png" alt="画像の内容を説明する日本語のalt" />
</div>
<div class="v-cover-copy">
  <div class="v-kicker">Category Label</div>
  <div class="v-cover-title">プロダクト名</div>
  <div class="v-cover-sub">サブコピー。<br/>2行まで。</div>
  <div class="v-cover-info">
    <div><span class="label">Date</span><span class="value">2026.08.26</span></div>
    <div><span class="label">Company</span><span class="value">会社名</span></div>
  </div>
  <!-- 日付の代わりにタグを置く場合は v-cover-meta + v-chip -->
</div>
```

```html
<!-- 章扉・結論（v-dark と併用） -->
<div class="v-statement">
  <div class="eyebrow">The problem</div>
  <div class="line">短い主張を、<br/><em>強調したい節だけ em で。</em></div>
  <div class="sub">2〜3行の補足。<br/>句点で改行を切る。</div>
</div>
```

```html
<!-- 画像1枚のページ（体験・世界観のみ。図解には使わない） -->
<div class="v-image-slide">
  <img src="/img/visual/quality.png" alt="…" />
</div>
<div class="v-image-copy">
  <div class="v-kicker">Label</div>
  <h2>1行の見出し<br/>2行まで</h2>
  <p>1文の説明。</p>
</div>
```

```html
<!-- Appendix 章扉（v-dark） -->
<div class="v-appendix-cover">
  <div class="v-kicker">Business</div>
  <h2>Appendix - ビジネス</h2>
  <p class="v-lead v-note-dark">収録内容を1文で。</p>
  <p class="v-note v-note-dark">補足。</p>
</div>

<!-- 締め: layout: center + class: visual-deck text-center v-center -->
<div class="v-end"><img src="/img/visual/network.png" alt="…" /></div>
<div class="v-end-copy">
  <div class="v-kicker">Product</div>
  <h2>最後に残したい一文。<br/>2行まで。</h2>
  <p>補足1文。</p>
</div>
```

## カード列

| クラス | 列 | 用途 |
| --- | --- | --- |
| `v-audience` | 3 | 「誰に / 何を / なぜ新しい」の定番3枚。`.accent` で1枚だけ反転 |
| `v-impact-grid` | 4 | 論点を4つに割る |
| `v-detail-grid` | 3（`-four` `-five` `-six`） | 機能・要素の並列 |
| `v-usecase-grid` | 3 | 各カードに `ul` を入れる比較 |
| `v-detail-columns` | 2（`-compact`） | 2項目の対比。`ul` 可 |
| `v-two-stack` | 縦2 | 理由を2つ積む。`v-metrics` の下に置くと収まりが良い |
| `v-duo` | 2 | Before / After。片側 `.accent` で反転 |
| `v-stream-grid` / `v-feature-inventory` | 3×3 | 収益源・API など9〜12項目の一覧 |
| `v-phase-grid` | 4 | フェーズごとに `ul` |
| `v-grid-compact` | — | 3行以上で高さが足りないときに併用 |

```html
<div class="v-audience">
  <article>
    <div class="ordinal">01</div>
    <h3>誰に売るか</h3>
    <p>説明を2〜3文。</p>
    <p class="use">顧客</p>
  </article>
  <article class="accent">…</article>
</div>

<div class="v-detail-grid v-detail-grid-five">
  <article><div class="index">聴く</div><h3>見出し</h3><p>説明。</p></article>
</div>

<div class="v-impact-grid">
  <article><div class="index">誰に</div><h3>提供対象</h3><p>説明。</p></article>
</div>

<div class="v-usecase-grid">
  <article>
    <div class="index">比較対象の名前</div>
    <h3>その特徴を一言で</h3>
    <ul><li>箇条書き</li><li>3項目まで</li></ul>
  </article>
</div>

<div class="v-duo">
  <article>
    <div class="giant">いま</div>
    <h3>現状の見出し</h3>
    <ul><li>…</li></ul>
    <p>まとめの1文。</p>
  </article>
  <article class="accent"><div class="giant">導入後</div>…</article>
</div>

<div class="v-two-stack">
  <article><h3>見出し</h3><p>説明。</p></article>
</div>

<div class="v-stream-grid">
  <article><span>01</span><div><h3>項目名</h3><p>説明。</p></div></article>
</div>

<div class="v-phase-grid">
  <article><div class="index">フェーズ1</div><h3>見出し</h3><ul><li>…</li></ul></article>
</div>
```

## フロー・プロセス

```html
<!-- 5段の横フロー -->
<div class="v-pipeline">
  <div class="node"><div class="num">01</div><h3>決済</h3><p>短い説明</p></div>
</div>

<!-- 4段のステップ -->
<div class="v-process">
  <article><div class="icon">01</div><h3>見出し</h3><p>説明。</p></article>
</div>

<!-- 矢印つきフロー（v-flow-detail-four / -five） -->
<div class="v-flow-detail v-flow-detail-four">
  <article><div class="index">01</div><h3>見出し</h3><p>説明。</p></article>
  <div class="arrow">→</div>
  <article>…</article>
</div>

<!-- 段階の推移 -->
<div class="v-timeline">
  <article><h3>初見</h3><p>この段階で起きること</p></article>
</div>
```

## 図解

```html
<!-- レイヤー構成図。v-arch-scope で自社提供範囲を囲う -->
<div class="v-arch">
  <div class="layer">
    <div class="name">接点<em>画面・アプリ</em></div>
    <div class="items"><span>Web</span><span>アプリ</span></div>
  </div>
  <div class="down">↓</div>
  <div class="v-arch-scope">
    <div class="v-arch-scope-label">自社が提供する範囲</div>
    <div class="layer core">
      <div class="name">中核<em>説明</em></div>
      <div class="items"><span>要素</span></div>
    </div>
  </div>
</div>

<!-- 中央にプラットフォーム、左右にステークホルダー -->
<div class="v-hub">
  <div class="v-hub-side"><div>事業者A</div><div>事業者B</div></div>
  <div class="v-hub-core">
    <div class="title">プロダクト名</div>
    <div class="sub">1行の説明</div>
    <div class="areas">
      <div><strong>領域名</strong><span>要素 / 要素 / 要素</span></div>
    </div>
  </div>
  <div class="v-hub-fan">…</div>  <!-- 基盤の外側に置く利用者 -->
</div>

<!-- 既存システムと自社モジュールの接続図 -->
<div class="v-bridge">
  <div class="v-bridge-col">
    <div class="v-bridge-head">既存システム</div>
    <div>既存のEC</div>
  </div>
  <div class="v-bridge-arrows"><span>⇄</span></div>
  <div class="v-bridge-col v-bridge-modules">
    <div class="v-bridge-head">提供する機能</div>
    <div>会員API</div>
  </div>
</div>

<!-- 分断・散在の図 -->
<div class="v-fragment">
  <div class="v-fragment-fan"><div class="label">利用者</div><p>1人が複数に分かれている状態</p></div>
  <div class="v-fragment-lines"><span></span><span></span><span></span></div>
  <div class="v-fragment-services"><div>サービスA</div><div>サービスB</div></div>
</div>

<!-- 1つの金額を複数へ配分する図 -->
<div class="v-split">
  <div class="source"><div class="amount">¥1,500</div><div class="label">月会費</div></div>
  <div class="fork">→</div>
  <div class="targets">
    <div><div><strong>受け取り先</strong><span>その根拠</span></div><div class="value">¥1,250</div></div>
  </div>
</div>

<!-- スマホ画面の横並び（UIモック画像を使う唯一の図） -->
<div class="v-phones">
  <div class="v-phone">
    <div class="v-phone-step">01</div>
    <div class="screen"><img src="/img/visual/screen-library.png" alt="…" /></div>
    <div class="caption">この画面で起きること</div>
    <div class="sub">画面名</div>
  </div>
</div>
```

## 数値・表

```html
<!-- 3つの大きな数値 -->
<div class="v-metrics">
  <article>
    <div class="num">12.6<span class="unit">%</span></div>
    <p>その数値が何を意味するか。出典と年を必ず添える。</p>
  </article>
</div>

<!-- 数値の帯（v-event-strip-two / -three） -->
<div class="v-event-strip v-event-strip-three">
  <div><strong>3,988億円</strong><span>市場名（年）</span></div>
</div>

<!-- 表: 列数クラス必須。-dense は行数が多いとき、-mixedhead はヘッダに固有名詞を置くとき -->
<div class="v-data-table v-data-table-four v-data-table-dense v-data-table-mixedhead">
  <div class="head">ケース</div><div class="head">顧客</div><div class="head">既存</div><div class="head">追加</div>
  <div class="strong">ケース1</div><div>…</div><div>…</div><div class="strong">…</div>
</div>

<!-- ○×の比較マトリクス。自社行に best を付ける -->
<div class="v-matrix">
  <div class="head"></div><div class="head">軸1</div><div class="head">軸2</div>
  <div class="row">競合A</div><div class="yes">●</div><div>—</div>
  <div class="row best">自社</div><div class="yes best">●</div><div class="yes best">●</div>
</div>

<!-- 顧客規模別プラン -->
<div class="v-plans">
  <article class="v-plan">
    <div class="name">小規模</div>
    <h3>特徴を一言で</h3>
    <div class="price">1文の説明。</div>
    <div class="v-plan-rows">
      <div><span>規模</span><strong>〜5千人</strong></div>
    </div>
  </article>
</div>

<!-- 会社概要 -->
<div class="v-company-list">
  <article>
    <div class="v-company-logo"><img src="/img/companies/logo.png" alt="…" /></div>
    <h3>会社名</h3>
    <div class="v-company-role">役割</div>
    <dl><div><dt>所在地</dt><dd>…</dd></div></dl>
  </article>
</div>
```
