# Atomic Design 構造チェック

## チェック対象

- Atomic ルート配下（`src/components/`, `components/`, `app/components/` のいずれか）
- 拡張子: `.tsx`, `.jsx`, `.ts`, `.js`, `.vue`
- ディレクトリ構成: `atoms/`, `molecules/`, `organisms/`, `pages/`, `layout/`

Nuxt の場合、フレームワークの `pages/` と衝突するため、Atomic の `pages/` は `components/pages/` に置かれている想定。もし Atomic の `pages/` レイヤーが見つからない場合は「pages 層なし」として扱い、pages 関連チェックはスキップする。

## チェック項目

### 1. 依存方向の逆転（🔴 Critical / 🟠 Important）

Atomic Design の依存方向は一方向: atoms → molecules → organisms → pages。下位層が上位層を import してはならない。

検出方法:
1. 各コンポーネントファイルの `import` 文（React/JSX）または `<script setup>` の `import` / `components:` 定義（Vue）を解析
2. 以下の依存を違反として検出:
   - `atoms/` が `molecules/`, `organisms/`, `pages/` を import → 🔴 Critical（atoms が pages を import する場合）/ 🟠 Important（それ以外）
   - `molecules/` が `organisms/`, `pages/` を import → 🟠 Important
   - `organisms/` が `pages/` を import → 🟠 Important
3. `layout/` は `pages/` からのみ使用されるべき。他の層からの import は違反（項目 3 で個別に扱う）

Nuxt の auto-import では明示的な import 文がなくても参照される。この場合は `<template>` 内のタグ名（PascalCase → kebab-case 変換）から使用先を推定し、`components/{layer}/` のどこにファイルがあるかで層を判定する。

### 2. コンポーネント配置の妥当性（🟠 Important）

コンポーネントの複雑さが配置層と合っているか確認する。

判定基準:
- **atoms**: 単一の HTML/JSX 要素またはそのラッパー。他の Atomic コンポーネントを使わない（または atoms のみ使用）。フック/composable は最小限（`useState` 程度）
- **molecules**: 2つ以上の atoms を組み合わせる。organisms は使わない
- **organisms**: molecules/atoms を組み合わせた機能単位。データ取得・ビジネスロジックに依存してよい
- **pages**: organisms を組み合わせ、layout でラップ。ルーティングから直接呼ばれる

検出する違反:
- atoms に配置されたファイルが molecules や organisms を import している → organisms 以上に移動すべき
- pages に配置されたファイルが他の Atomic コンポーネントを一切使っていない → より下位の層に移動すべき
- molecules が atoms を1つも使っていない → atoms に移動すべき

### 3. layout の直接使用（🟠 Important）

`layout/` パッケージは `pages/` からのみ使用されるべき。

検出方法:
1. `layout/` を import しているファイルを列挙
2. `pages/` 以外のディレクトリから import しているファイルを違反として報告

Next.js の App Router では `app/**/layout.tsx` がフレームワークの layout として扱われる。Atomic の `layout/` はこれと別物であり、`components/layout/` などに置かれている想定。両者を混同しないよう `app/layout.tsx` は本チェックの対象外とする。

### 4. HTMX/RSC フラグメント用コンポーネントの配置（🟡 Suggestion）

Next.js の Server Components や部分的な CSR で返される断片用のコンポーネントが適切な層にあるか。

- 断片は通常 molecules または organisms レベル
- pages に配置された断片用コンポーネントは下位層への移動を提案

### 5. 未使用コンポーネント（🟢 Minor）

定義されているが他のテンプレートから参照されていないコンポーネントを検出する。

検出方法:
1. 各コンポーネントファイルの default/named export を列挙
2. 他のファイルからの参照（import + JSX 使用、または Vue template でのタグ使用）を検索
3. ルーターからの直接参照も確認（Next.js の `app/**/page.tsx` や `pages/**/*.tsx`、Nuxt の `pages/**/*.vue`）
4. どこからも参照されていないコンポーネントを報告

Nuxt の auto-import 対象コンポーネントは、template 内のタグ名でも参照される。PascalCase / kebab-case の両方で検索する。
