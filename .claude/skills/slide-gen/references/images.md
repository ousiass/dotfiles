# キービジュアルの生成（nano-banana MCP）

## 原則

- **図解は画像にしない。** 構成図・フロー・比較・数値はすべて `visual.css` の CSS で組む。
  理由: 差分レビューと文言修正ができるため。
- **画像を使うのは表紙・体験・クロージングだけ。** 抽象的または実写的なキービジュアルに限る。
- **画像内に文字を入れない。** 日本語ラベルは必ず HTML 側に持たせる。
  生成 AI の描く文字は崩れ、修正もできない。
- 1つのデッキで 4〜7 点。多用すると資料の密度が落ちる。

## 生成手順

1. デッキ全体で共通する画風を先に1文で決める（例: 「暗い会場の実写風、青と紫の照明、人物の顔は写さない」）。
   全カットのプロンプトにこの1文を入れて画風を揃える。
2. `mcp__nano-banana__generate_image` で生成する。プロンプトは英語。
   必ず `no text, no letters, no logos, no watermarks` を含める。
3. 気になる箇所は `mcp__nano-banana__edit_image` / `continue_editing` で詰める。
4. 採用したものを `public/img/visual/<用途>.png` にコピーする（`cover.png` `experience.png` など用途名で）。
   生成物の置き場（`generated_imgs/` など）は `.gitignore` に入れ、採用分だけコミットする。
5. `<img>` の `alt` には画像の内容を日本語で書く。PDF 化・読み上げの両方で使われる。

## プロンプトの型

```
<被写体と状況>, <構図>, <光と色>, <質感>,
16:9 aspect ratio, cinematic, no text, no letters, no logos, no watermarks
```

例:

```
Fans holding up smartphones at a live music venue, seen from behind the crowd,
deep blue and magenta stage lighting, shallow depth of field, photographic,
16:9 aspect ratio, cinematic, no text, no letters, no logos, no watermarks
```

## UI モック（例外）

スマホ画面を並べる `v-phones` に限り、UI モック画像を使ってよい。ただし:

- 画面内のラベルはすべてプレースホルダのバー・ブロックにする（文字を書かせない）
- 説明の日本語は `.caption` / `.sub` として HTML 側に置く
- 端末の枠と配置は `v-phones` の CSS が持つので、画像は画面の中身だけにする

プロンプトに `UI mockup, placeholder bars instead of text, no readable characters` を加える。

## MCP が使えない場合

`mcp__nano-banana__*` が無い環境では画像を生成せず、以下のいずれかにする。

- 表紙・クロージングを `v-statement`（`v-dark`）に差し替え、画像なしで成立させる
- `public/img/visual/` に置くべきファイル名と用途を README に列挙し、後から差し込めるようにする

画像が無くても資料は成立する。プレースホルダ画像は入れない。

## ビルドとの関係

`slides.md` が参照する画像パスは**必ず実在させる**。存在しないと `slidev build` が
`Module not found` で失敗する（`public/` 配下でも同じ）。

テンプレートの表紙・締めは画像なしの `v-dark` で出発し、画像を用意した時点で
`v-dark` を外して `v-cover` / `v-end` を有効化する。画像を使わないと決めたページは
`v-dark` のまま残す。
