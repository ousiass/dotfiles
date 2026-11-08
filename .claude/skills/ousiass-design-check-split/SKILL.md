---
name: ousiass-design-check-split
description: ousiass-design-check の基準を観点グループごとの並列 agent で当て、検出漏れを減らす（試作）。
user-invocable: true
---

# ousiass-design-check-split

`ousiass-design-check` と**同じ基準・同じ重大度・同じ Issue 形式**で、チェックを観点グループに分けて**並列 agent** で行う。1 agent が見る項目を減らし、読み飛ばし（スライダーが標準 UI のまま・進捗バーの見た目・トークン外の色、など）を防ぐ。コードは変更しない。

`ousiass-design-check` との違いは 2 点だけ:

1. 項目を 4 グループに分け、グループごとに別 agent が**自分の項目だけ**を当てる
2. agent は担当した**全項目の確認状況（coverage）**を返す。返らない項目は 1 回だけ再実行し、それでも無ければ「未確認」にする（黙って飛ばさせない）

基準の正本は `../ousiass-design-check/references/check-criteria.md`（ここに複製しない。ずれる原因になる）。Issue / レポートの形式は `../ousiass-design-check/templates/report.md`。

## 引数

- `<path>...` — 対象のファイル・ディレクトリ（複数可）
- `#<PR>` — `gh pr diff --name-only` の変更ファイルを対象にし、変更行とその周辺を見る
- `--out issue|file` — 出力先を聞かずに決める（無人実行用）。`issue` = カテゴリ別 GitHub Issue、`file` = `ousiass-design-check-report.md`。省略時は `AskUserQuestion` で聞く
- `--groups A,C` — 指定グループだけ実行（再実行用）。省略時は全グループ
- 引数なし: `AskUserQuestion` で対象を聞く

URL 指定（画面の確認）は扱わない。画面を見るときは `/ousiass-design-check` を使う。

## グループ

| G | 観点 | 項目 | 読むガイドの節（`ousiass-design-guide` の `references/brand-guide.md`） |
|---|---|---|---|
| A | 色 | C1〜C8、O6（チャート色） | 1. 色（コアトークン・状態色・プリズム・ダーク背景） |
| B | 文字と形 | T1〜T8、S1〜S5 | 2. タイポグラフィ、3. 形・余白・線 |
| C | UI 部品・スクロールバー | O7〜O12（ボタン・スイッチ・スライダー・進捗／ローディング・独自部品）、B1〜B6（スクロールバー） | 4. UI 部品、7. P1 部品、8. P2 部品、10. スクロールバー |
| D | 重なり・動き・アイコン | O1〜O5、I1〜I2、M1〜M6 | 4. のオーバーレイ、5. モーション、6. P0 骨格 |

項目 ID と節の対応はこの表だけで決める。新しい項目が `check-criteria.md` に増えたら、ID の文字（C / T / S / I / M / O / B）でこの表のどれかに入れる。**表に無い ID を見つけたら実行前に止めて報告する**（黙って捨てない）。

## 手順

### 1. 準備（メイン。軽く済ませる）

1. 対象ファイルの一覧を作る（`git ls-files <path>`。`node_modules` / `dist` / 生成物 / ロックファイルは除く）。`#<PR>` なら変更ファイル
2. 使用フレームワークとトークン定義ファイル（`tokens*` / `variables.css` / `tailwind.config.*` / `theme.*` / `:root` を持つ CSS）のパスを把握する。HALT の検知は `refine-sweep` フェーズ1 手順2 と同じ。HALT なら `*.templ`・Lit（`.ts`）・CSS を対象に含め、生成物（`*_templ.go`）は除く
3. 仕様書・docs の「Ousiass デザインガイド準拠」節にある**承認済みの逸脱**（逸脱表）を読み、一覧にする
4. `brand-guide.md` 7 行目の取り込み時点 SHA を控える（レポートの基準欄）

メインはここ以降コードを読まない。

### 2. 並列 check（1 メッセージで全グループの Agent を同時に起動）

`Agent(subagent_type: review)`、`model` は渡さない（`harness-model`）。グループごとに下記を渡す。`<…>` は必ず埋める:

```
Ousiass 共通デザインガイドの準拠チェックを、担当項目だけ行ってください。コードは変更しない。Issue も作らない。

担当グループ: <G と観点名>
担当項目: <ID 列挙>

読むもの（これだけ。他の項目は読まない）:
1. `<check-criteria.md の絶対パス>` から担当項目の行だけ: rg -n '^\| (<ID を | で連結>) ' <パス>
   と、末尾の「機械検出のレシピ」のうち、コメントに担当 ID が書かれている行。**コメントの表記は `T1/T2/T3`（スラッシュ）・`M1〜M3`（範囲）・`O10 / O11` などまちまちなので、範囲・スラッシュで担当 ID を含む行（例: 担当が M2 なら `M1〜M3` の行）も担当に含める**。文字列の一致だけで探さない
2. `<brand-guide.md の絶対パス>` の担当の節: <節の見出し>
3. 対象: <ファイル一覧 / PR の変更ファイルと変更行>
   トークン定義ファイル: <パス>。承認済みの逸脱（指摘しない）: <一覧。無ければ「なし」>

手順:
- 担当項目ごとにレシピで疑いを洗い出し、**該当行を読んで**判定する。ヒットは疑いであって指摘ではない
- 項目ごとに必ず coverage に `checked`（根拠にした確認の要約を `note` に 1 行）か `unchecked`（理由）を書く。**担当項目が 1 つでも coverage に無い返答は不合格**
- 0 件でも、読んで確認できていない項目は `unchecked`。「問題なし」と書かない
- ガイドに規定がない部品・値は指摘にせず `guide_gap` に書く。ガイドの要約と公開ページが食い違っていたら `guide_drift`
- 担当外の項目に当たる問題を見つけても指摘しない（別グループが見る）。無視できない重大なもの（🔴 相当）だけ `out_of_scope` に 1 行で書く
- 指摘には `ファイル:行` とガイドの定め（項目 ID）と推奨（トークン名・コード例）を付ける

最終メッセージは JSON 1 行のみ:
{"group":"<G>","coverage":{"<ID>":{"status":"checked|unchecked","note":"<1行>"}},"findings":[{"id":"<ID>","severity":"red|orange|yellow|green","file":"<パス>","line":<N>,"title":"<要約>","guide":"<ガイドの定め>","problem":"<問題>","recommend":"<推奨>"}],"guide_gap":[{"where":"<ファイル:行>","what":"<内容>","proposal":"<提案>"}],"guide_drift":["<食い違い>"],"out_of_scope":["<ファイル:行 — 1行>"],"failure":null}
失敗時: {"group":"<G>","coverage":{},"findings":[],"failure":"<1行で原因>"}
```

### 3. coverage 検証（メイン）

返答ごとに、担当項目の ID が `coverage` に全部あるか確認する:

- 欠けている ID がある、または JSON が壊れている → その**欠けた ID だけ**を担当にして同じグループを **1 回だけ**再実行する
- 再実行でも欠ける / `failure` → その ID を「未確認（agent が確認状況を返さなかった）」として扱い、実行は止めない
- `status: unchecked` の項目は、理由付きで「未確認」に載せる（問題なしにしない）

### 4. 統合（メイン）

- 全グループの `findings` を、項目 ID の文字（C / T / S / I / M / O / B）でカテゴリごとにまとめる
- `(id, file, line)` が同じものは 1 件にする。同じ行に別の項目が当たるのは別指摘のまま残す
- `out_of_scope` は、同じ `ファイル:行` が他グループの `findings` に無い場合だけ、該当カテゴリの 🟡 の候補としてチャットに列挙する（Issue にはしない）
- `guide_gap` は「ガイド未収載（追加提案）」、`guide_drift` はチャット報告のみ（Issue に入れない）

### 5. 出力

`ousiass-design-check` のフェーズ3 と同じ。`--out` が無ければ `AskUserQuestion` で出力先を聞く（GitHub Issue カテゴリ別〔推奨〕/ ローカル MD。PR 指定なら PR コメントも）。

- GitHub Issue はカテゴリごと（指摘があるカテゴリだけ）に 1 件。タイトル `ousiass-design-check: <カテゴリ名>(<カテゴリ ID>)(<ブランチ名>, <YYYY-MM-DD>)`、本文は `../ousiass-design-check/templates/report.md` の「カテゴリ別 Issue の形式」。親 Issue は作らない。**形式を変えない**（`/design-fix #<Issue番号>` と `ousiass-design-sweep` がそのまま読めるように）
- 基準欄に取り込み時点 SHA、「未確認」に手順 3 の結果、「承認済みの逸脱」に手順 1 の件数を書く
- 指摘 0 件なら Issue を作らず、確認した範囲（coverage の `checked` 項目数）と未確認の項目を報告して終える

チャットの報告: Issue の URL 一覧（カテゴリ別）、件数（カテゴリ別・重大度別）、グループごとの確認状況（担当項目数 / checked 数 / unchecked 数）、未確認の項目、ガイドのズレ、`out_of_scope` の候補。

## ルール

- コードを変更しない。ブランチ作成・コミット・PR もしない。Issue を作るのはメインの手順 5 だけ（agent には作らせない）
- 基準を `check-criteria.md` から複製・要約してこのスキルや agent プロンプトに書き写さない。agent には**パスと ID** を渡し、自分で読ませる
- 推測で指摘しない。コードを読み、ガイドの定めと突き合わせて裏付けを取る
- 承認済みの逸脱は指摘しない。逸脱表に無いガイド外れは指摘する
- 汎用の a11y・レスポンシブ・Props 設計は対象外（`design-review`）
- coverage に無い項目を「問題なし」にしない。agent を 1 回再実行しても出なければ未確認
- 全グループを逐次に起動しない（1 メッセージで同時に起動する。並列にする意味がなくなる）
