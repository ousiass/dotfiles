---
name: ousiass-design-check
description: Ousiass プロダクトの実装・PR・画面が共通デザインガイドに沿っているか確認するとき。
user-invocable: true
---

# ousiass-design-check

実装・PR・画面が Ousiass 共通デザインガイド（brand-guide）に準拠しているかを確認し、指摘を Issue またはレポートにする。コードは変更しない。

## 正と役割分担

- **正は brand-guide**: https://ousiassllc.github.io/brand-guide/ 。基準は `references/check-criteria.md`（`ousiass-design-guide` スキルの `references/brand-guide.md` が要約）。食い違ったらガイドが正
- `design-review`: プロジェクト自身のデザイン基盤（Tailwind 設定・テーマ・既存ライブラリ）を基準にした汎用レビュー。**置き換えない**。本スキルは Ousiass 共通ガイド準拠に特化し、a11y・レスポンシブ・Props 設計など汎用観点は `design-review` に任せる
- `ousiass-design-guide`: 仕様書・docs にガイドを取り込む側。本スキルは確かめる側
- `visual-review`: 実描画のスクリーンショットレビュー。画面の見た目を見るときは併用する

## 前提条件

- Claude Code 環境
- `gh` CLI（PR 差分・GitHub Issue 出力時）

## 引数

- パス指定 (例: `/ousiass-design-check src/components`): そのファイル・ディレクトリを対象
- PR 指定 (例: `/ousiass-design-check #123`): `gh pr diff` の変更行と、変更ファイルの周辺を対象
- URL 指定: 画面をブラウザで開いて確認（ツールがあれば。無ければ「画面未確認」と書く）
- 引数なし: `AskUserQuestion` で対象を確認する

## フェーズ1: 対象と基準の把握

1. 対象（コード / PR 差分 / 画面）と使用フレームワークを把握する
2. プロジェクトのトークン定義（`tokens.*`, `variables.css`, `tailwind.config.*`, `theme.ts` 等）を読み、ガイドのトークン名・値と対応しているかを確認する
3. 仕様書・docs に「Ousiass デザインガイド準拠」節があれば読む（承認済みの逸脱は指摘から除く）
4. `references/check-criteria.md` と、`ousiass-design-guide` スキルの `references/brand-guide.md` を読み、後者 7 行目の取り込み時点コミット SHA を控える（レポートの基準欄に使う）。ガイドの値に迷ったら公開ページ（`index.html` の `#typography` `#scrollbar`、`tokens-preview.html` の `#heading-compact` `#scrollbar` など）で確認する。公開ページが読めなければ要約のみで判定し、レポートの「未確認」に「公開ページ未確認」と書く
5. 対象をリストアップし、TaskCreate でタスク化する（ファイル数が多ければディレクトリ単位）

## フェーズ2: 準拠チェック

`references/check-criteria.md` の項目を順に当てる。

| カテゴリ | 主な観点 |
|---|---|
| C 色 | プリズムはキービジュアルのみ / トークン使用 / フォーカスは `--focus` / 状態色はくすんだ色 / ライト・ダーク |
| T タイポ | Sora + Noto Sans JP + JetBrains Mono / SemiBold は見出しとボタンのみ / サイズスケール / 見出しタグとサイズは独立（T6〜T8: H1 必須にしない・`h1`=40 や 24 / 18 / 16 を強制しない） |
| S 形・余白 | 角丸・間隔レシピ・影はモーダルのみ / ブレークポイント |
| I アイコン | Iconoir 16 / 20 / 24 |
| M モーション | 静かだけど動きがある / トークン使用 / バウンス・プリズム禁止 / reduced-motion |
| O 部品・オーバーレイ | 中央モーダル基本・外側クリックで閉じる / トースト / コーチマークはグレー ink / ガイドにない部品を使わない |
| B スクロールバー | 縦・横・両方向 / 8px・矢印なし・透明 track・`--mute` thumb / Chromium の優先関係 / forced-colors / ネイティブ操作の維持（range とは別） |

1. 機械検出のレシピで疑いを洗い出し、該当行を読んで判定する。**grep・タグの有無・CSS 文字列は候補検出のみ**で、見出しは役割 CSS・computed style・文脈、スクロールバーはブラウザ優先関係・computed style・実動作と照合してから決める
2. 画面を確認できる場合は、ライト・ダークの両方と reduced-motion で見る。スクロールバーは縦 / 横 / 両方向と通常 / hover / active、可能ならブラウザ・OS・forced-colors の違いとキーボード操作（Tab → 縦は ↑↓・PageUp / PageDown・Space・Home / End、横は ← →）を見る。確認できない項目は「未確認」と書き、問題なしと書かない
3. 承認済みの逸脱（docs の逸脱表）は指摘しない。逸脱表に無いガイド外れは指摘する
4. 各項目を 4 区分（準拠 / 指摘 / 仕様上の例外 / 未確認）に分ける。仕様上の例外（Firefox の thin 近似・OS のオーバーレイ・forced-colors での OS 標準など）は環境・理由・機能維持の証拠を付け、例外を理由に未実装を準拠にしない。静的確認だけなら「実操作済み」と書かない
5. 各指摘に `ファイル:行`（画面は URL と要素）、ガイドの定め（項目 ID）、推奨を付ける

## フェーズ3: レポート生成

1. `AskUserQuestion` で出力先を確認する:
   - **GitHub Issue**（推奨）: タイトル `ousiass-design-check: ガイド準拠レポート(<ブランチ名>, <YYYY-MM-DD>)`
   - **ローカル MD ファイル**: `ousiass-design-check-report.md`
   - **PR 指定のとき**: 上記に加え、PR コメント（要約のみ）も選べる
2. レポート形式は `templates/report.md` を参照。重大度（🔴🟠🟡🟢）と「ファイル / 問題 / 推奨」の形は `design-review` と同じなので、修正は `/design-fix #<Issue番号>` に渡せる
3. 件数（重大度別）、仕様上の例外、未確認の項目、ガイドのズレ（要約と公開ページの食い違い）を報告する。指摘が 0 件なら Issue を作らず、確認した範囲と未確認の範囲を報告して終える

## 重大度の基準

重大度は `references/check-criteria.md` の各項目に従う（🔴 ガイドの明示禁止に直接違反 / 🟠 ガイドからの逸脱 / 🟡 提案 / 🟢 軽微）。

## ルール

- コードを変更しない。ブランチ作成・コミット・PR もしない
- 推測で指摘しない。コードを読み、ガイドの定めと突き合わせて裏付けを取る
- 指摘にはファイルパスと行番号（または画面と要素）、項目 ID を示す
- ガイドにないことを根拠に指摘しない。ガイドが定めていない領域は「ガイドに規定なし」として扱い、必要なら「ガイドへの追加提案」に分ける。**H1 の有無・h3 開始、`h1`=40 や見本の 24 / 18 / 16 との不一致だけでは指摘にしない**（T6〜T8）
- 🔴🟠 は必ずレポートに含める。🟡🟢 は明確なメリットがある場合のみ
- 汎用の a11y・レスポンシブ・Props 設計は対象外（`design-review` を案内する）。ただしスクロール領域の操作性（キーボード・フォーカス・領域名。B6）は本スキルでも確認する
- TaskCreate/TaskUpdate で進捗を管理する
