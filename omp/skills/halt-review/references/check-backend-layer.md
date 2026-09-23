# Go レイヤードアーキテクチャチェック

## チェック対象

- `internal/` 配下の Go パッケージ
- 各レイヤーの import 文

## レイヤー定義

```
domain/       ← 最下層。他のレイヤーに依存しない
repository/   ← domain のみに依存
service/      ← domain, repository に依存
web/handler/  ← service, domain に依存。repository を直接使わない
router/       ← handler を参照してルートを定義
```

## チェック項目

### 1. レイヤー依存方向の違反（🟠 Important）

各レイヤーが許可された依存先のみを import しているか確認する。

検出する違反:
- `domain/` が `repository/`, `service/`, `web/` を import → 🟠（ドメイン層は外部依存禁止）
- `repository/` が `service/`, `web/` を import → 🟠（repository は domain のみ）
- `service/` が `web/handler/` を import → 🟠（service は handler に依存しない）
- `web/handler/` が `repository/` を直接 import → 🟠（handler は service を経由すべき）

検出方法:
1. 各 `.go` ファイルの `import` ブロックを解析
2. パッケージパスからレイヤーを判定
3. 許可されていない方向の import を検出

### 2. Huma Input/Output 構造体の欠如（🟠 Important）

Huma で登録された API ルートに適切な Input/Output 構造体が定義されているか確認する。

チェックポイント:
- `huma.Register` 等の呼び出しでジェネリクス型引数に Input/Output 構造体が渡されているか
- Input 構造体にバリデーションタグ（`required`, `minLength`, `maxLength` 等）が適切に設定されているか
- Output 構造体に `Body` フィールドが定義されているか
- `doc` タグや `example` タグで OpenAPI ドキュメントが充実しているか → 🟡 Suggestion

### 3. ハンドラのレスポンス型の一貫性（🟡 Suggestion）

同一リソースに対する SSR ハンドラと API ハンドラが一貫したデータ構造を使っているか。

- SSR ハンドラがテンプレートに渡すデータと、API ハンドラが返す JSON の元データが同じ domain モデルから派生しているか
- ハンドラ内で独自の構造体を定義してデータ変換している場合、domain モデルとの乖離がないか
