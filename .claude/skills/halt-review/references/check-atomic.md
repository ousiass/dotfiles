# Atomic Design 構造チェック

## チェック対象

- `web/` 配下の Templ テンプレートファイル（`.templ`）
- ディレクトリ構成: `atoms/`, `molecules/`, `organisms/`, `pages/`, `layout/`

## チェック項目

### 1. 依存方向の逆転（🟠 Important）

Atomic Design の依存方向は一方向: atoms → molecules → organisms → pages。下位層が上位層を import してはならない。

検出方法:
1. 各 `.templ` ファイルの import 文を解析
2. 以下の依存を違反として検出:
   - `atoms/` が `molecules/`, `organisms/`, `pages/` を import
   - `molecules/` が `organisms/`, `pages/` を import
   - `organisms/` が `pages/` を import
3. `layout/` は `pages/` からのみ使用されるべき。他の層からの import は違反

### 2. コンポーネント配置の妥当性（🟠 Important）

コンポーネントの複雑さが配置層と合っているか確認する。

判定基準:
- **atoms**: 単一の HTML 要素またはそのラッパー。他の Templ コンポーネントを使わない（または atoms のみ使用）
- **molecules**: 2つ以上の atoms を組み合わせる。organisms は使わない
- **organisms**: molecules/atoms を組み合わせた機能単位。ビジネスロジックに依存してよい
- **pages**: organisms を組み合わせ、layout でラップ。ルートハンドラから直接呼ばれる

検出する違反:
- atoms に配置されたファイルが molecules や organisms を import している → organisms 以上に移動すべき
- pages に配置されたファイルが他のコンポーネントを一切使っていない → より下位の層に移動すべき

### 3. layout の直接使用（🟠 Important）

`layout/` パッケージは `pages/` からのみ使用されるべき。

検出方法:
1. `layout` パッケージを import しているファイルを列挙
2. `pages/` 以外のディレクトリから import しているファイルを違反として報告

### 4. HTMX フラグメント用コンポーネントの配置（🟡 Suggestion）

HTMX の部分更新で返される HTML フラグメント用のコンポーネントが適切な層に配置されているか。

- フラグメントは通常 molecules または organisms レベル
- pages に配置されたフラグメント用コンポーネントは下位層への移動を提案

### 5. 未使用コンポーネント（🟢 Minor）

定義されているが他のテンプレートから参照されていないコンポーネントを検出する。

検出方法:
1. 各 `.templ` ファイルの公開コンポーネント（大文字始まりの関数）を列挙
2. 他のファイルからの参照（import + 呼び出し）を検索
3. ハンドラからの直接参照も確認（ページやフラグメントコンポーネント）
4. どこからも参照されていないコンポーネントを報告
