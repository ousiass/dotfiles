# Ousiass デザインガイド準拠チェック項目

正は brand-guide（https://ousiassllc.github.io/brand-guide/ ）。値の詳細は `ousiass-design-guide` スキルの `references/brand-guide.md`（要約）。食い違ったらガイドが正。
「ガイドにない部品・値・モーションは使わない」が全項目の前提。

重大度: 🔴 重大（ガイドの明示禁止に直接違反し、ブランドを崩す）/ 🟠 重要（ガイドからの逸脱）/ 🟡 提案（トークン化・整理）/ 🟢 軽微。

## C. 色

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| C1 | プリズム（`--prism-*`、violet→blue→cyan→green→yellow のグラデ）はロゴ・ヒーロー・キービジュアルだけ。ボタン・リンク・入力欄・バッジ・チャート・アクティブ表示・モーションに使わない | 主ボタンの虹色グラデ、チャート系列にプリズム色、プリズムのボーダーアニメ | 🔴 |
| C2 | 色はトークン（`--ink` `--bone` `--mute` `--surface` `--border` `--accent` `--accent-soft` と状態色）。ハードコード hex / rgb / Tailwind 既定色を使わない | `#333`、`text-gray-500`、`bg-blue-600` | 🟠（値がガイドと一致していてもトークン未使用なら 🟡） |
| C3 | フォーカスリングは `--focus`（`2px solid` / offset 2）。フォームの focus は `--focus` 青（`--ring` 40%）。それ以外の青・アクセント色を UI に足さない | `outline: none` だけ、独自の青ボタン、リンクが青 | 🟠 |
| C4 | 状態色は次の 4 トークンだけ。値は必ずこの HEX と照合する（Light / Dark）: `--success` `#3d5c4a` / `#8fafa0`、`--warning` `#7a6a3a` / `#c4b87a`、`--danger` `#7a4545` / `#c49a9a`、`--info` `#4a5a6a` / `#9aabbc`。トークン定義（`:root` / `[data-theme=dark]` / Tailwind theme 等）の値がこれと違えば違反。ステータスのピル・バッジ・アラートは「文字 `var(--状態)`・枠 `color-mix(in srgb, var(--状態) 40%, transparent)`・地 `color-mix(in srgb, var(--状態) 10%, transparent)`・`--r-full`」だけ。ピンク・ローズ・パステル・ネオンなど 4 トークン以外の色相を状態表示に使わない（中立の「下書き」だけは `--mute`）。状態はアイコン＋文言＋色で伝え、色だけに頼らない | `color: red`、`bg-rose-100 text-pink-700`、`#f9a8d4` のピル、`--danger: #ef4444`、色だけのステータス表示 | 🔴（4 トークン外の色相・定義値の不一致）/ 🟠（淡い塗りのルール逸脱） |
| C5 | ライト / ダークの両方で成立する。トークンが `[data-theme=dark]` 等で切り替わる | ダークで文字が読めない、片方のみの値 | 🟠 |
| C6 | `--mute` は補助テキスト・キャプション。本文の長文に使わない（コントラスト不足） | 段落本文が `--mute` | 🟡 |
| C7 | プロダクト独自のパレットを作らない。主操作は `--accent`（インク色） | `--brand-primary` の新設 | 🟠 |
| C8 | 純黒 `#000` / `#000000` / `rgb(0,0,0)` / `bg-black` をページ背景・大きな面に使わない。ページ背景は `--bone`（Light `#f5f5f4` / Dark `#050505`＝ほぼ黒）、カード・パネル・サイドバーは `--surface`（Light `#ffffff` / Dark `#141414`）、区切りは `--border`（`#e7e7e5` / `#2a2a2a`） | ダークの `body{background:#000}`、`bg-black`、サイドバーだけ `#000` | 🟠 |

## T. タイポグラフィ

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| T1 | フォントは Sora + Noto Sans JP（`font-family: Sora, "Noto Sans JP", sans-serif`）とコード・数値の JetBrains Mono。OFL 以外を持ち込まない | Inter / システムフォント指定、商用フォントの読み込み | 🟠 |
| T2 | SemiBold (600) は**見出しとボタンだけ**。ナビ・リンク・ラベル・本文は Regular (400)。Bold (700) 以上を多用しない | ナビリンクが `font-semibold`、本文に `font-bold` | 🟠（700 以上の多用）/ 🟡（ナビ・リンクの 600） |
| T3 | サイズはスケール `xs` 12 / `sm` 14 / `base` 16 / `lg` 18 / `xl` 24 / `2xl` 32 / `3xl` 40 から選ぶ。本文は 16px Regular、14px 未満を本文にしない | 13px、15px、20px の直指定 | 🟡（スケール外）/ 🟠（本文が 14px 未満） |
| T4 | 行間はスケールの値（本文 1.8 前後）。日本語長文を詰めない | `line-height: 1.2` の本文 | 🟡 |
| T5 | コード・桁を揃える数値は JetBrains Mono。テーブルの数値列は Mono・右寄せ | 数値列が左寄せ・可変幅 | 🟡 |

## S. 形・余白・線

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| S1 | 角丸は `--r-*`。入力・ボタン `md` 8 / カード `lg` 12 / モーダル `xl` 16 / ピル・アバター `full` / タグ・チェック `sm` 4 | ボタン 10px、カード 20px | 🟡 |
| S2 | 余白は 4px 基準の `--s-*`（4/8/12/16/24/32/48/64）。UI ごとの間隔レシピ（`--gap-*` `--pad-card*` `--menu-item-h` 等）に合わせる | カード padding 20、メニュー項目間 10 | 🟡 |
| S3 | 影はモーダルだけ（`--shadow-modal`）。カード・パネルは影なし、`1px solid var(--border)` で区切る | カードに `box-shadow` | 🟡 |
| S4 | 空状態・ドロップ領域は `1px dashed`。強調枠は `1px var(--mute)` | 太い枠、二重枠 | 🟢 |
| S5 | セクション間は 48〜72（標準 `--gap-section` 72）。ブレークポイントは `--bp-*`（640 / 768 / 1024 / 1280）、ガターはモバイル `--s-4`・デスクトップ `--s-6` | 独自ブレークポイント 900 | 🟡 |

## I. アイコン

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| I1 | UI アイコンは Iconoir（MIT）。他のアイコンセットを混ぜない（ブランドロゴは別） | Lucide / Font Awesome / Material Icons の併用 | 🟠 |
| I2 | サイズは 16 / 20 / 24（`--icon-sm/md/lg`）。32 は empty state のみ。ストローク ≈1.5・`currentColor` | 18px、色のハードコード、塗りアイコン | 🟡 |

## M. モーション

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| M1 | 動かすのは状態変化・出現/退出を伝えるときだけ。トークン（`--motion-fast` 120 / `base` 180 / `slow` 280 / `fade-in` 320 / `fade-out` 240 と `--ease-*`）を使う。ホバーは色・背景のみ ≤180ms、フォーカスは即時〜120ms | ホバーで位置・サイズが動く、独自 duration | 🟡 |
| M2 | 禁止: バウンス / スプリング / scale ポップ（使うなら最大 1.02）/ 装飾だけのループ・視差・大きな移動 / UI 上のプリズム（虹色）モーション / 定義トークン以外の 300ms 超 UI トランジション | `cubic-bezier` のオーバーシュート、背景パララックス | 🟠（プリズムモーションは 🔴） |
| M3 | `prefers-reduced-motion: reduce` に対応する。移動・スライドは無効化、必要な opacity フェードは ≤100ms またはなし。スピナーなど処理中表示は維持 | reduced-motion の分岐が無い | 🟠 |
| M4 | ボタンとクローズ（アイコンボタン）の押下は小さなリップル（クリック点から円が広がって消える・280ms ease-out） | リップルなし、別種のエフェクト | 🟡 |
| M5 | 出現はフェードイン 320ms（ease-out）、退出はフェードアウト 240ms（ease-in）。移動は 4〜8px。ガイドに定義のないモーションパターンを足さない | 独自のズーム・フリップ演出 | 🟡 |
| M6 | スケルトンのパルスは任意。reduced-motion では静止 | 派手なシマー、reduced-motion で動き続ける | 🟡 |

## O. 部品・オーバーレイ

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| O1 | オーバーレイは**中央モーダルが基本**。共有・短い選択肢はボトムシート可。モーダル・シート・ドロワー・ポップオーバー・コマンドパレットは**外側（スクラム）クリックで閉じる**。スクラムはオーバーレイと一緒にフェード | 外側クリックで閉じないモーダル、全画面ページで確認を取る | 🟠 |
| O2 | 確認・破壊的操作は中央モーダル（`--r-xl`・`--shadow-modal`）。ドロワー＝持続するサイド文脈（詳細・フィルタ）、ボトムシート＝短い選択肢で混同しない | 破壊的操作をトーストで確認 | 🟠 |
| O3 | トーストは画面下中央・端から 24・高さ 40・ピル・1 行の短文・3 秒（アクション付き 5 秒）・同時 1 つ・アクションは 1 つまで。エラー詳細・フォーム検証・確認・破壊的操作に使わない。戻せる作業結果はスナックバー | 右上に複数積む、10 秒表示、検証エラーをトースト | 🟠 |
| O4 | z-index は `--z-*`（base 0 / dropdown 100 / sticky 200 / drawer 300 / modal 400 / toast 500） | `z-index: 9999` | 🟡 |
| O5 | コーチマーク（オンボーディング）はスポットライトが `--ink` グレーのベースリング＋広がって薄れるパルス＋外側ディム。**focus 青は使わない**。チップは `--surface` カード・同時に 1 つ | 青いパルス、複数同時表示 | 🟠 |
| O6 | チャートの系列色は `--success` `--warning` `--info` `--mute` `--ink`（無彩色系）。プリズム・塗りつぶしグラデ禁止。系列は最大 4〜5 | 虹色の棒グラフ | 🟠（プリズムは 🔴） |
| O7 | ボタンは主（`--accent`）/ サブ / ゴースト / 危険。SemiBold・`--r-md`・小は高さ 32・disabled は opacity .4。ナビ・リンクは Regular。ページネーションの「もっと見る」は無限スクロールより明示ボタン | ボタン以外のリンクが SemiBold、disabled が別の見た目 | 🟡 |
| O8 | **ガイドにない部品を使わない**。独自ウィジェットは案件ガイドで定義する（共通ガイドに発明しない）。必要ならガイドへ追加提案が先 | 共通 UI 層に独自の評価ウィジェットを新設 | 🟠 |
| O9 | 印刷・PDF がある場合: ink on bone、ナビ・ドロワー・トースト等は `@media print` で非表示、状態色は文言併記、プリズム装飾は印刷しない | ダークテーマのまま印刷 | 🟡 |
| O10 | スイッチはガイドの見た目必須（OS / ブラウザ標準のまま出さない）: トラック 36×20・つまみ 14・`--r-full`、OFF は `--accent-soft`＋1px `--border`、ON は `--accent`（つまみ `--bone`）、フォーカスは `--ring`、ラベル Regular 15（SemiBold にしない） | 素の `<input type="checkbox" role="switch">`、緑の ON、iOS 風の別サイズ | 🟠 |
| O11 | スライダーはガイドの見た目必須: トラック高さ 4・`--r-full`、未充填 `--accent-soft`・充填 `--accent`、つまみ 16 の円・`--surface`＋1px `--border`（ダークも同じ構造）。`accent-color` だけに頼らず track / thumb を明示スタイル。値表示は Mono `--mute` 可 | 素の `<input type="range">`、`accent-color` のみ、青い充填 | 🟠 |

## 機械検出のレシピ（対象ディレクトリを `<dir>` に置き換える）

ヒットは「疑い」。必ず該当行を読んで判定し、`ファイル:行` を根拠にする。

```bash
# C1/C2 プリズム値・ハードコード色（ガイドの prism hex と一般的な hex / rgb）
rg -n -i '#(8b6ad4|a78bfa|4a72d0|60a5fa|3aaaba|22d3ee|3d9a7a|34d399|b8a24a|fbbf24)\b|--prism-' <dir>
rg -n -i '#[0-9a-f]{3,8}\b|rgba?\(|hsla?\(' <dir> --glob '!**/{tokens*,variables.css,tailwind.config.*,theme.*}' --glob '!**/*.svg'
# C2 Tailwind 既定色
rg -n '\b(text|bg|border|ring|from|to|via)-(red|green|blue|yellow|gray|slate|zinc|neutral|stone|orange|amber|lime|emerald|teal|cyan|sky|indigo|violet|purple|fuchsia|pink|rose)-[0-9]{2,3}\b' <dir>
# C3 フォーカス
rg -n 'outline:\s*(none|0)|outline-none|focus:outline-none' <dir>
# T1/T2/T3 フォント・ウェイト・サイズ
rg -n 'font-family|font-weight:\s*(600|700|800|900)|font-(semibold|bold|extrabold|black)' <dir>
rg -n -i 'font-size:\s*[0-9.]+(px|rem)|text-\[[0-9.]+(px|rem)\]' <dir>
# S1/S2/S3 角丸・余白・影
rg -n 'border-radius:\s*[0-9.]+px|rounded-\[|box-shadow' <dir>
# I1 アイコンセット
rg -n -i "from '(lucide|@fortawesome|react-icons|@mui/icons|@heroicons|feather)|lucide-|fa-solid|material-icons" <dir>
# M1〜M3 モーション
rg -n 'transition|animation|@keyframes|cubic-bezier|transform:\s*scale|duration-[0-9]+' <dir>
rg -n 'prefers-reduced-motion|motion-reduce' <dir>
# O1/O4 オーバーレイ・z-index
rg -n 'z-index:\s*[0-9]{4,}|z-\[[0-9]+\]|z-(10|20|30|40|50)\b' <dir>
rg -n -i 'modal|dialog|drawer|scrim|backdrop|overlay' <dir>
# C4 状態色の照合（許可外の色相・定義値の不一致）
rg -n -i -- '--(success|warning|danger|info)\s*:' <dir>
# ↑ 値が 3d5c4a / 8fafa0 / 7a6a3a / c4b87a / 7a4545 / c49a9a / 4a5a6a / 9aabbc 以外なら違反（トークン定義ファイルも対象）
rg -n '\b(text|bg|border|ring)-(red|green|yellow|pink|rose|fuchsia|orange|amber|emerald|lime)-[0-9]{2,3}(/[0-9]+)?\b|\b(bg|text)-(pink|rose|red|green)-50\b' <dir>
rg -n -i 'badge|pill|chip|status|tag' <dir>
# ↑ ヒットした部品の色が 4 トークン＋淡い塗り（文字 / 枠40% / 地10%）かを読んで判定
# C8 純黒
rg -n -i '#000\b|#000000\b|rgb\(\s*0\s*,\s*0\s*,\s*0\s*\)|\bbg-black\b' <dir>
# O10 / O11 標準コントロール
rg -n 'type=["'"'"']?(range|checkbox)|role=["'"'"']?switch|accent-color' <dir>
```

- `rg` が無ければ `grep -rnE` に読み替える（`--glob '!X'` は `--exclude=X` / `--exclude-dir=X` に置き換える）
- トークン定義ファイル（`tokens*` / `variables.css` / `tailwind.config.*` / `theme.*` で、ガイドの値を `:root` 等に定義する箇所）は C2 の対象外。C2 のコマンドは除外済み。**C4 の定義値照合ではこの除外を適用しない**（定義そのものの誤りを拾うため）
- 検出が 0 件でも、読んで確認できていない項目は「未確認」と書き、問題なしと書かない
