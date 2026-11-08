# Ousiass デザインガイド準拠チェック項目

正は brand-guide（https://ousiassllc.github.io/brand-guide/ ）。値の詳細は `ousiass-design-guide` スキルの `references/brand-guide.md`（要約）。食い違ったらガイドが正。本書の基準の固定 SHA は `5d816f8`（フル SHA `5d816f8fde675938647d43d521441c40d9a13b77`）。見出しは `index.html#typography` / `tokens-preview.html#heading-compact`、スクロールバーは `index.html#scrollbar` / `tokens-preview.html#scrollbar`。
「ガイドにない部品・値・モーションは使わない」が全項目の前提。

重大度: 🔴 重大（ガイドの明示禁止に直接違反し、ブランドを崩す）/ 🟠 重要（ガイドからの逸脱）/ 🟡 提案（トークン化・整理）/ 🟢 軽微。禁止・逸脱・提案の区別は、各項目の「重大度」欄の値に従う（項目ごとに、正本の記述の強さに合わせてある）。**ガイドにない禁止を作らない**（ガイドが定めていないことは指摘にせず、「ガイドへの追加提案」に分ける）。

判定は 4 区分: **準拠** / **指摘**（重大度付き）/ **仕様上の例外**（環境差など。根拠付きで記録）/ **未確認**（確認できていない。準拠扱いにしない）。詳細は末尾の「判定の区分と証拠」。

## C. 色

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| C1 | プリズム（`--prism-*`、violet→blue→cyan→green→yellow のグラデ）はロゴ・ヒーロー・キービジュアルだけ。ボタン・リンク・入力欄・バッジ・チャート・アクティブ表示・モーションに使わない | 主ボタンの虹色グラデ、チャート系列にプリズム色、プリズムのボーダーアニメ | 🔴 |
| C2 | 色はトークン（`--ink` `--bone` `--mute` `--surface` `--border` `--accent` `--accent-soft` と状態色）。ハードコード hex / rgb / Tailwind 既定色を使わない | `#333`、`text-gray-500`、`bg-blue-600` | 🟠（値がガイドと一致していてもトークン未使用なら 🟡） |
| C3 | フォーカスリングは `--focus`（`2px solid` / offset 2）。フォームの focus は `--focus` 青（`--ring` 40%）。それ以外の青・アクセント色を UI に足さない | `outline: none` だけ、独自の青ボタン、リンクが青 | 🟠 |
| C4 | 状態色は `--success` `--warning` `--danger` `--info`（くすんだ無彩色寄り）。鮮やかな原色の赤・緑を使わない。状態はアイコン＋文言＋色で伝え、色だけに頼らない | `color: red`、色だけのステータス表示 | 🟠 |
| C5 | ライト / ダークの両方で成立する。トークンが `[data-theme=dark]` 等で切り替わる | ダークで文字が読めない、片方のみの値 | 🟠 |
| C6 | `--mute` は補助テキスト・キャプション。本文の長文に使わない（コントラスト不足） | 段落本文が `--mute` | 🟡 |
| C7 | プロダクト独自のパレットを作らない。主操作は `--accent`（インク色） | `--brand-primary` の新設 | 🟠 |

## T. タイポグラフィ

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| T1 | フォントは Sora + Noto Sans JP（`font-family: Sora, "Noto Sans JP", sans-serif`）とコード・数値の JetBrains Mono。OFL 以外を持ち込まない | Inter / システムフォント指定、商用フォントの読み込み | 🟠 |
| T2 | SemiBold (600) は**見出しとボタンだけ**。ナビ・リンク・ラベル・本文は Regular (400)。Bold (700) 以上を多用しない | ナビリンクが `font-semibold`、本文に `font-bold` | 🟠（700 以上の多用）/ 🟡（ナビ・リンクの 600） |
| T3 | サイズはスケール `xs` 12 / `sm` 14 / `base` 16 / `lg` 18 / `xl` 24 / `2xl` 32 / `3xl` 40 から選ぶ。本文は 16px Regular、14px 未満を本文にしない | 13px、15px、20px の直指定 | 🟡（スケール外）/ 🟠（本文が 14px 未満） |
| T4 | 行間はスケールの値（本文 1.8 前後）。日本語長文を詰めない | `line-height: 1.2` の本文 | 🟡 |
| T5 | コード・桁を揃える数値は JetBrains Mono。テーブルの数値列は Mono・右寄せ | 数値列が左寄せ・可変幅 | 🟡 |
| T6 | 見出しタグ（h1〜h6）は文書の意味構造、サイズは視覚的な役割で、**独立**して指定されている。サイズ・ウェイトは役割クラスの CSS や computed style で確認する。**`h1`=40 / `h2`=32 / `h3`=24 や、正本コンパクト見本の h3 24 → h4 18 → h5 16 を合否基準にしない**（用途例・見本であり規範ではない。h1 が 24 でも準拠）。見出しの間隔（`--gap-h1` `--gap-h2` `--gap-h3`）もタグ番号ではなく見た目の大・小で決まる | 小さく見せるためだけに h1 → h4 へ下げ、同じ画面の文書階層が崩れていることを文脈込みで確認できる（タグを保って CSS で調整するのが定め） | 🟡 |
| T7 | **H1 は必須ではない**。H1 なし・h3 / h4 始まりは、既存シェルへの埋め込み画面などの文脈で準拠。H1 を置くためだけに大見出しを足さない。途中でレベルを飛ばす（例: h2 → h4）場合は文脈上の理由を確認し、確認できなければ「未確認」。**H1 の有無・h3 開始だけを理由に指摘しない** | 理由なく h2 → h4 へ飛ばす / H1 を置くためだけに追加した大見出し | 🟡 |
| T8 | 見出しを全画面・全見出しで一律に縮小しない（役割間のサイズ差を保つ）。サイズは既存スケール（12 / 14 / 16 / 18 / 24 / 32 / 40）から役割に合わせて選ぶ。本文 16px Regular（行間 1.8 前後）・通常ボタン 16px / 小ボタン 14px・見出しとボタンだけ 600 は維持。カードタイトル（`.cd-t` 相当）と説明文を混同しない | 全見出しを 14〜16 に揃えて階層が消える / 説明文までカードタイトルと同じ 600 | 🟡（本文が 14px 未満になるなら T3 で 🟠） |

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

## B. スクロールバー（縦・横・両方向）

対象は `overflow: auto` 等でコンテンツをスクロールする領域。値を変える range スライダー（トラック 4px・つまみ 16px）とは別物。基準は `ousiass-design-guide` の `references/brand-guide.md` §10。**CSS 文字列だけで合否を確定しない**（優先関係・computed style・実動作で確認する）。

| ID | 確認すること | 違反の例 | 重大度 |
|---|---|---|---|
| B1 | **縦・横・両方向**のスクロール領域すべてに同じ設計を当てる。カスタム可能な環境（WebKit / Blink）で、一方向だけカスタムし他方向が OS 標準の太く明るいバーのまま、は逸脱 | 縦は `::-webkit-scrollbar { width }` だけで `height` が無く、横は標準の太いバー | 🟠 |
| B2 | 見た目の実値: 矢印なし（`::-webkit-scrollbar-button` 非表示）・透明 track / corner・thumb は `--mute`（Light `#6b6b6e` / Dark `#8b8b8e`）で角丸 999px・WebKit / Blink で幅・高さ 8px。hover は `color-mix(in srgb, var(--ink) 35%, var(--mute))`、active / drag は同 65%。標準側は `scrollbar-width: thin; scrollbar-color: var(--mute) transparent`。Light / Dark の bone・surface 上で見えること | 幅 12px、矢印が残る、thumb が accent やハードコード色、track に塗り、hover / active 色の指定なし | 🟠（幅・矢印・thumb 色）/ 🟡（hover / active のみ未指定） |
| B3 | **優先関係**: Chromium 121 以降は `scrollbar-width` / `scrollbar-color` が `auto` 以外だと `::-webkit-scrollbar` を無視する。`@supports selector(::-webkit-scrollbar)` の中で標準 2 プロパティを `auto` に戻す。標準 → 擬似要素の順に並べるだけでは不可。Chromium の computed style（`scrollbarWidth` が `auto`）と実描画（幅 8px・矢印なし・hover 色）で確認する | 標準指定を残したまま擬似要素を書き、Chromium で 8px / hover / active が効かない | 🟠 |
| B4 | カスタムは `@media (forced-colors: none)` に限定する。`forced-colors: active` や OS が太いバーを要求する設定では OS の見やすさを優先し、カスタムを外す | forced-colors に関係なく常にカスタムを適用 | 🟠 |
| B5 | range スライダーの規定（トラック 4px・つまみ 16px）をスクロールバーに流用しない。スクロールバーの規定を range に流用しない | スクロールバー thumb の幅 16px、トラック 4px | 🟠 |
| B6 | ネイティブスクロールを維持する。独自 JS のドラッグ機構・装飾 SVG への置き換え、バーの常時非表示（`scrollbar-width: none`・`::-webkit-scrollbar { display: none }`）や `overflow: hidden` で問題を隠してスクロール・キー操作を失わせることをしない。Tab で領域へフォーカスでき（領域名付き）、縦は ↑↓ / PageUp / PageDown / Space / Home / End、横は ← → で動く。ホイール・トラックパッド・タッチ・ドラッグ以外の代替操作を維持する | バーを隠した上にキーボードで動かせない、独自 JS スクロールバー | 🟠 |

### 環境差による仕様上の例外

次は「仕様上の例外」として記録でき、指摘にしない。**環境・設定・理由・スクロール機能が保たれている証拠**を必ず添える。例外を未実装の隠れ蓑にしない（根拠がなければ B1〜B6 の指摘か「未確認」）。

- Firefox: thin と色による近似。厳密な 8px・個別の hover / drag 色は要求しない。矢印は出ないことが多い。標準指定のみの比較見本で Chromium に矢印が残るのは推奨の完成形ではない
- macOS・モバイルのオーバーレイ（自動非表示）、OS の常時表示設定、ブラウザの制約。全環境で同一 px・同一表示は保証しない
- `forced-colors: active` や OS が太いバーを要求する設定で、カスタムを外して OS 標準を使っている

## 判定の区分と証拠

| 区分 | 使うとき |
|---|---|
| 準拠 | 基準を満たすと、実装・computed style・実動作のいずれかで裏付けが取れた |
| 指摘 | 基準から外れていると裏付けが取れた。項目 ID・重大度・推奨を付ける |
| 仕様上の例外 | 環境差などガイドが許容する理由があり、機能が維持されている（上の例外節） |
| 未確認 | 確認していない・確認できない（未検証のブラウザ・実機・OS 設定・キーボード操作・Light / Dark を含む）。**準拠扱いにしない** |

- grep・タグの有無・CSS 文字列は**候補の検出のみ**。該当行と周辺の CSS・文脈を読み、必要なら computed style・実動作で確かめてから区分を決める
- 静的な確認（コードを読んだだけ）では「実操作済み」と書かない。実ブラウザで確認した範囲と、していない範囲を分けて書く
- レポートに残す証拠: 項目 ID・対象（`ファイル:行`、または URL と要素）・参照 SHA / アンカー・Light / Dark・縦 / 横 / 両方向・通常 / hover / active・ブラウザ / OS / 設定（forced-colors・OS の常時表示など）・操作結果・スクリーンショット等

### 判定例（回帰確認）

| 例 | 判定 | 根拠 |
|---|---|---|
| 役割クラスで 24px にした h1 | 準拠 | T6: h1 でも 40 への拡大は求めない |
| 既存シェル内で H1 なし、h3 / h4 から始まる | 準拠 | T7: H1 の不在・h3 開始だけで指摘しない |
| 「h1 は常に 40px」を要求するチェック / コンパクト見本の 24 / 18 / 16 を全画面に要求するチェック | チェック自体の誤り（このスキルでは行わない） | T6: 用途例・見本は規範ではない |
| 小さくするためだけに h1 → h4 へ変更し、文書構造が崩れていると文脈込みで確認できる | 指摘 🟡 | T6 |
| カスタム可能な同じ環境で縦だけ対応し、横は OS 標準の太く明るいバー | 指摘 🟠 | B1 |
| バーを隠してスクロール・キー操作まで失わせる / range の 4px・16px を流用 / Chromium で標準プロパティが残り 8px・hover 指定が無効 | 指摘 🟠 | B6 / B5 / B3 |
| Firefox で thin 近似・hover 色なし、または forced-colors で OS 標準 | 仕様上の例外（環境・理由・機能維持の証拠が要る） | B 節の例外 |
| Safari や実機で操作を試していない | 未確認（検証済みと書かない） | 判定の区分 |

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
# T6〜T8 見出し（候補検出のみ。タグの有無・番号で合否にしない）
rg -n -i '<h[1-6][ >]|role="heading"' <dir>
rg -n '(^|[[:space:],}>])h[1-6][[:space:]]*[,{]' <dir>
# B1〜B6 スクロールバー（候補検出のみ。優先関係・computed style・実動作で確認する）
rg -n 'overflow(-x|-y)?[[:space:]]*:[[:space:]]*(auto|scroll)|overflow-(x-|y-)?(auto|scroll)' <dir>
rg -n '::-webkit-scrollbar|scrollbar-(width|color|gutter)|forced-colors|@supports[[:space:]]+selector' <dir>
rg -n 'scrollbar-width[[:space:]]*:[[:space:]]*none|scrollbar-none|no-scrollbar' <dir>
rg -n -i 'type="range"|\[type=range\]|::-webkit-slider|::-moz-range' <dir>
```

- `rg` が無ければ `grep -rnE`（`-i` 付きは `grep -rniE`）に読み替える（`--glob '!X'` は `--exclude=X` / `--exclude-dir=X` に置き換える）。T6〜T8・B の行は `grep -rnE` でもそのまま動く書き方にしてある。`::-webkit-scrollbar` ブロック内の `display: none`（`-button` 以外）は複数行にまたがるので、2 行目の検出行の前後を読んで確認する
- トークン定義ファイル（`tokens*` / `variables.css` / `tailwind.config.*` / `theme.*` で、ガイドの値を `:root` 等に定義する箇所）は C2 の対象外。上記コマンドは除外済み
- 検出が 0 件でも、読んで確認できていない項目は「未確認」と書き、問題なしと書かない
