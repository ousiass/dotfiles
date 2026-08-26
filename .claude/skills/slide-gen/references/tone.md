# トーン & マナー

Step 2 で決め、Step 3 で `visual.css` の `:root` とスタイル方針に反映する。
**執筆を始めてから変えない。** 途中で変えると全ページの手直しになる。

決める項目は6つ。**スタイル / 配色 / ロゴ** / 文体 / 情報密度 / ラベル言語。

スタイルと配色は独立して選べる（3 × 4 = 12 通り）。
**スタイルを変えないと、配色だけ変えても同じ顔の資料になる。** 用途に合わせて必ず選ぶ。

## 1. スタイルプリセット

カードの形・罫線・角丸・見出しの太さ・バナーの見え方を決める。
`visual.css` の `:root` にある**意匠トークン**を差し替えるだけで切り替わる。

### A. Editorial（既定）

角ゼロ、カード上端に 3px の色帯、白地に細罫、詰まった太字見出し、濃紺ベタのバナー。
硬めで密度が高い。提案書・技術資料に合う。

`visual.css` の既定値がこれ。**追記不要**。

### B. Soft

角丸と影で面を浮かせ、罫線と色帯をなくす。淡い地で `.accent` を示す。
やわらかく親しみのある印象。社内向け、report、サービス紹介に合う。

```css
/* visual.css の末尾に追記する */
:root {
  --v-radius: 14px;
  --v-card-border: none;
  --v-card-topline: 0;
  --v-card-shadow: 0 2px 12px rgba(16, 24, 40, 0.07);
  --v-card-accent-bg: color-mix(in srgb, var(--v-accent) 8%, var(--v-white));
  --v-card-pad: 1.3rem 1.35rem;
  --v-h2-weight: 750;
  --v-h2-tracking: -0.02em;
  --v-kicker-mark: 0;
  --v-kicker-tracking: 0.14em;
  --v-banner-bg: color-mix(in srgb, var(--v-accent) 6%, var(--v-white));
  --v-banner-color: var(--v-navy);
  --v-banner-label: var(--v-accent-text);
  --v-banner-border: 1px solid color-mix(in srgb, var(--v-accent) 25%, var(--v-white));
}
```

### C. Minimal

カードの地と枠をなくし、上端 1px の罫線と余白だけで区切る。新聞・論文に近い静かな面。
情報量が多いデッキ、堅い相手、印刷前提のときに合う。

```css
/* visual.css の末尾に追記する */
:root {
  --v-radius: 0;
  --v-card-border: none;
  --v-card-topline: 1px;
  --v-card-bg: transparent;
  --v-card-accent-bg: transparent;
  --v-card-shadow: none;
  --v-card-pad: 0.9rem 0 0;
  --v-h2-size: 2.2rem;
  --v-h2-weight: 700;
  --v-h2-tracking: -0.01em;
  --v-kicker-mark: 0;
  --v-kicker-tracking: 0.2em;
  --v-banner-bg: transparent;
  --v-banner-color: var(--v-navy);
  --v-banner-label: var(--v-accent-text);
  --v-banner-border: 1px solid var(--v-line);
}
```

### 意匠トークン一覧

個別に詰めたい場合はこのトークンだけを触る。**セレクタに直接値を書かない。**

| トークン | 効果 |
| --- | --- |
| `--v-radius` | 角丸。カード・バナー・表に効く |
| `--v-card-bg` / `--v-card-border` / `--v-card-shadow` | カードの地・枠・影 |
| `--v-card-topline` | カード上端の色帯の太さ。`0` で消える |
| `--v-card-accent-bg` | `.accent` カードの地。色帯を消すプリセットで差別化に使う |
| `--v-card-pad` | カード内の余白 |
| `--v-h2-size` / `--v-h2-weight` / `--v-h2-tracking` | 見出しの大きさ・太さ・字間 |
| `--v-kicker-mark` | kicker 前の横線の長さ。`0` で消える |
| `--v-kicker-tracking` / `--v-kicker-case` | kicker の字間・大文字化 |
| `--v-banner-bg` / `--v-banner-color` / `--v-banner-label` / `--v-banner-border` | 結論バナーの地・文字・ラベル・枠 |
| `--v-sans` | 本文フォント |

## 2. 配色プリセット

`visual.css` の `:root` ブロックを丸ごと差し替える。**他の箇所に色を直書きしない。**
記載のコントラスト比は実測値（WCAG 相対輝度比）。

### A. 紺 × インディゴ（既定）

落ち着いた企業資料向け。提案・技術説明の両方に無難に効く。

```css
:root {
  --v-bg-light: #f7f8fb;
  --v-bg-dark: #0a1030;
  --v-navy: #0a1030;
  --v-blue: #2b3a86;
  --v-accent: #4f46e5;
  --v-accent-text: #4338ca;
  --v-accent-on-dark: #8b93ff;
  --v-magenta: #d6339b;
  --v-magenta-text: #b21f80;
  --v-white: #ffffff;
  --v-ink: #101828;
  --v-muted: #667085;
  --v-line: #dcdfeb;
  --v-line-dark: rgba(255, 255, 255, 0.16);
  --v-mono: 'JetBrains Mono', ui-monospace, monospace;
}
```

白文字/dark 18.6:1、ink/light 16.7:1、accent-text/light 7.4:1、accent-on-dark/dark 6.8:1。

### B. 墨 × 一色差し

色数を抑えた硬めの資料向け。技術説明・社内報告で、色より構造で読ませたいとき。

```css
:root {
  --v-bg-light: #f6f7f8;
  --v-bg-dark: #14171c;
  --v-navy: #14171c;
  --v-blue: #3f4855;
  --v-accent: #1f6feb;
  --v-accent-text: #155ec4;
  --v-accent-on-dark: #6ea8fe;
  --v-magenta: #c2410c;
  --v-magenta-text: #9a3412;
  --v-white: #ffffff;
  --v-ink: #14171c;
  --v-muted: #6b7280;
  --v-line: #dfe2e6;
  --v-line-dark: rgba(255, 255, 255, 0.16);
  --v-mono: 'JetBrains Mono', ui-monospace, monospace;
}
```

白文字/dark 18.0:1、accent-text/light 5.7:1、accent-on-dark/dark 7.4:1。
`--v-accent` は罫線・大きな数字などの構造色専用（4.3:1）。本文の色には `--v-accent-text` を使う。

### C. 深緑 × 琥珀

環境・一次産業・ヘルスケアなど、青系が業界イメージと合わないとき。

```css
:root {
  --v-bg-light: #f6f8f6;
  --v-bg-dark: #0c221c;
  --v-navy: #0c221c;
  --v-blue: #215c4d;
  --v-accent: #0f766e;
  --v-accent-text: #0b5c56;
  --v-accent-on-dark: #5eead4;
  --v-magenta: #b45309;
  --v-magenta-text: #92400e;
  --v-white: #ffffff;
  --v-ink: #0f1a17;
  --v-muted: #5f6b66;
  --v-line: #dbe3df;
  --v-line-dark: rgba(255, 255, 255, 0.16);
  --v-mono: 'JetBrains Mono', ui-monospace, monospace;
}
```

白文字/dark 16.7:1、accent-text/light 7.3:1、accent-on-dark/dark 11.3:1。

### D. ブランドカラー指定（対話で決める）

プリセットに当てはまらない場合は、**プライマリカラー1色から全トークンを導出する**。
手で色を並べず、必ずスクリプトを使う（コントラスト基準を機械で担保するため）。

#### 手順

1. `AskUserQuestion` でプライマリカラーを聞く。選択肢はコーポレートカラー・プロダクトカラー・
   既存資料に合わせる等を挙げ、**HEX は自由入力**で受け取る。
   ロゴ画像やサイトがあれば、そこから拾った色を候補として提示する
2. 強調色（資料全体で1〜2箇所だけ使う色）を使うか聞く。指定がなければ自動生成する
3. 導出する

```bash
bun <skill>/scripts/derive-palette.mjs "#2b6cb0"
bun <skill>/scripts/derive-palette.mjs "#2b6cb0" --accent "#d6339b"   # 強調色も指定
bun <skill>/scripts/derive-palette.mjs "#2b6cb0" --json               # 機械処理する場合
```

4. 出力された `:root` を `visual.css` の `:root` と差し替える
5. コントラスト表を確認する。終了コード 0 = 全基準を満たす、1 = 満たさない項目がある

#### 導出の中身

| トークン | 決め方 |
| --- | --- |
| `--v-accent` | 指定色。light 背景で 3:1 未満なら、罫線と数字が見えるまで自動で暗くする |
| `--v-accent-text` | 指定色を light 背景で 4.5:1 まで暗くしたもの（本文で使う色） |
| `--v-accent-on-dark` | 指定色を dark 背景で 4.5:1 まで明るくしたもの |
| `--v-on-accent` | accent をベタ塗りした上の文字色。白と navy のうちコントラストが高い方 |
| `--v-navy` / `--v-bg-dark` | 指定色の色相を保ったまま明度を 11% まで落としたもの |
| `--v-magenta` 系 | 強調色。指定がなければ色相を +150° 回して生成 |
| `--v-bg-light` / `--v-line` / `--v-ink` / `--v-muted` | 指定色の色相をわずかに含む無彩色寄りの値 |

**指定色が明るい場合**（オレンジ・黄・ライトグリーン等）、`--v-accent` は自動で暗く調整される。
ブランド色をそのまま出したい場合は `--v-accent` を指定色に戻し、
細い罫線には使わず面（バナー・バッジ）だけに使う運用にする。

#### 決めたあとの確認

配色を当てたら、必ず**実際にレンダリングして目で見る**。

```bash
make build && make png
```

数値が基準を満たしていても、色相によっては重く見えたり沈んで見えたりする。
2〜3ページ確認してから本文の執筆に入る。

## 3. 文体

| 方針 | 使う場面 | 例 |
| --- | --- | --- |
| 常体（言い切り） | 提案・技術説明。既定 | 会員基盤と配信基盤を1つにまとめる |
| 敬体（です・ます） | 社外報告、目上への説明 | 会員基盤と配信基盤を1つにまとめます |

デッキ内で混在させない。h2 は方針にかかわらず常体または名詞句で書く（敬体の h2 は長くなる）。

そのほか全デッキ共通:

- 主語を省かない。「対応した」ではなく「誰が何に対応したか」
- 修飾を削る。「非常に」「しっかりと」「きちんと」は消す
- 同じ概念を別語で言い換えない。用語は資料内で1つに固定する
- 社内用語・略語は初出で1度だけ定義し、以降は略語を使う

## 4. 情報密度

| プリセット | 1ページの目安 | 使う場面 |
| --- | --- | --- |
| 薄め | カード3枚 / 本文40字以内 / 箇条書き3行 | 対面プレゼン。投影して話しながら見せる |
| 標準（既定） | カード3〜5枚 / 本文60字以内 / 箇条書き5行 | 対面と PDF 送付の兼用 |
| 厚め | カード5〜6枚 / 本文80字以内 / 箇条書き7行 | PDF 送付のみ。読み物として単体で成立させる |

「対面で話す」なら薄め、「送って読んでもらう」なら厚め。兼用なら標準。
Appendix は本編より1段階厚くしてよい。

## 5. ラベル言語

`v-kicker` に置く小見出しラベルの言語。

- **英語**（既定）— `What we do` `Before / After`。視覚的なアクセントとして効く
- **日本語** — `提供内容` `現状と導入後`。英語が読み手の負担になる場合

どちらでも h2 と本文は日本語。混在させない。

## 6. ロゴ

デッキで使う場所は3つ。**使うか使わないかを最初に決める。** 後から入れると表紙の余白設計が崩れる。

| 場所 | クラス | 扱い |
| --- | --- | --- |
| 表紙 | `.v-cover-logo` | kicker の上。高さ 2rem。置かない選択もある |
| フッター（全ページ） | `.deck-footer .logo` | `global-bottom.vue` で会社名テキストと差し替える。高さ 0.85rem、控えめに |
| 締め | `.v-end-copy .v-cover-logo` | 中央寄せ。表紙に置いたなら締めにも置くと収まる |

### 決めること

1. **ロゴを使うか** — 使わない場合は会社名のテキストのみ（既定）。社外向けなら通常は使う
2. **どこに置くか** — 表紙とフッターの両方 / 表紙のみ / フッターのみ
3. **dark 背景での見え方** — 表紙・章扉・締めは dark になる。
   濃色のロゴはそのままでは沈む。**白抜き版を用意するか、どちらの背景でも成立する単色ロゴを使う**

### 置き場所

`public/img/logo.svg`（白抜き版は `logo-white.svg`）。SVG があれば SVG を使う。
PNG しかない場合は背景が透過しているものを使う。JPG は避ける（背景が白く出る）。

### 使わない場合

`global-bottom.vue` の会社名テキストがそのままクレジットになる。
表紙は `v-cover-info` の Company 欄が会社名を示すので、ロゴがなくても成立する。

## 反映手順

1. スタイルプリセット（A 以外）を `visual.css` の末尾に追記する
2. 配色プリセットで `visual.css` の `:root` を差し替える
3. ロゴを使う場合は `public/img/` に置き、`global-bottom.vue` と表紙のコメントを有効化する
4. 文体・密度・ラベル言語を作業メモに書き、全ページで守る
5. `slide/README.md` の「デザインルール」に選んだスタイルと配色、理由を1行残す
