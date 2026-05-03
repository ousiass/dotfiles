---
name: stitch-deploy
description: Stitchモックzipを展開しNetlifyデプロイ可能な構造に変換する
user-invocable: true
---

# Stitch Deploy

Stitchで生成したモックのzipファイルを展開し、Netlifyにそのままアップロードできるディレクトリ構造に変換する。

## 引数

```
/stitch-deploy [zipファイルパス] [出力先ディレクトリ(省略時: zipと同階層の mock/)]
```

## Stitchのzip構造

```
stitch/
├── p_001/
│   ├── code.html    ← ページのHTML
│   └── screen.png   ← スクリーンショット
├── p_002/
│   ├── code.html
│   └── screen.png
├── p_032_csv/       ← サフィックス付きもある
│   ├── code.html
│   └── screen.png
└── stitch_precision_blue/
    └── DESIGN.md    ← デザインシステム文書（そのまま配置）
```

## 変換後の構造（Netlify対応）

```
mock/
├── index.html              ← ナビゲーション付きトップページ（自動生成）
├── login/
│   ├── index.html          ← code.html をリネーム
│   └── screen.png
├── attendance-list/
│   ├── index.html
│   └── screen.png
├── ...
└── stitch_precision_blue/
    └── DESIGN.md
```

## ワークフロー

### Phase 1: 準備

1. 引数からzipファイルパスを取得。未指定なら作業ディレクトリ内の `stitch*.zip` を探す
2. zipを一時ディレクトリに展開する（出力先はPhase 2でユーザーに確認する）

### Phase 2: ページ解析とディレクトリ名決定

各 `p_XXX/` ディレクトリについて：

1. `code.html` から以下の順でページ名を推定：
   - `<title>` タグのテキスト（「- Stitch Time」「| Stitch Time」「Stitch Time -」等のアプリ名部分を除去）
   - `<h1>` タグのテキスト（アプリ名のみの場合はスキップ）
   - `<h2>` タグのテキスト
   - いずれも取れない場合はディレクトリ名のサフィックス部分（例: `p_032_csv` → `csv`）
2. 推定したページ名を英語のURLスラッグに変換：
   - 日本語名は英訳してからスラッグ化（例: 勤怠一覧 → attendance-list）
   - 英語名はそのまま小文字+ハイフン区切り（例: Shift Pattern Management → shift-pattern）

**全ページのマッピング表をユーザーに提示し、出力先ディレクトリも含めて確認を取る。**

提示形式：
```
番号 | Stitchディレクトリ | 推定ページ名 | 変換先ディレクトリ
-----|-------------------|-------------|------------------
1    | p_001             | ログイン      | login
2    | p_002             | 打刻実行      | stamp
...
```

- ユーザーが修正指示を出したら反映する
- 出力先ディレクトリのパスもこのタイミングで確認する
- 承認されるまで次に進まない

### Phase 3: ファイル配置

1. 出力先ディレクトリが既に存在する場合、上書きするかユーザーに確認
2. 各ページについて：
   - 変換先ディレクトリを作成
   - `code.html` → `index.html` にリネームして配置
   - `screen.png` をそのまま配置
3. `stitch_precision_blue/` などの非ページディレクトリはそのまま配置
4. ルートの `index.html` を生成（全ページへのナビゲーションリンク付き）

### Phase 4: index.html生成

ルートの `index.html` はシンプルなナビゲーションページ：

- プロジェクト名（Stitchの `<h1>` やデザインシステムから取得）をタイトルに
- 全ページへの相対リンク一覧
- 各リンクにページ名（日本語）とスクリーンショットのサムネイルを表示
- Tailwind CDNを使用したスタイリング（Stitchの出力に合わせる）

### Phase 5: 確認

1. 出力ディレクトリの `tree` を表示
2. ページ数とファイルサイズの概要を報告
3. 「このまま `netlify deploy --dir=mock/` でデプロイできます」と案内

## ルール

- ユーザー確認なしにファイルを上書きしない
- マッピング表は必ずユーザーに提示して承認を得る
- `code.html` の中身は一切変更しない（リネームのみ）
- 一時展開ディレクトリは処理完了後に削除する
