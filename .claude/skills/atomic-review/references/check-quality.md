# コンポーネント品質チェック

## チェック対象

- Atomic ルート配下のすべてのコンポーネントファイル

## チェック項目

### 1. 命名規則の不統一（🟠 Important）

コンポーネント名・ファイル名・ディレクトリ名が統一されているか確認する。

判定基準（プロジェクトの慣習を優先し、混在があれば違反として報告）:
- **React (Next.js / 素の React)**: コンポーネント名は PascalCase、ファイル名は PascalCase または kebab-case（プロジェクトで統一）
- **Vue (Nuxt / 素の Vue)**: SFC ファイル名は PascalCase（多くの Nuxt 慣習）または kebab-case。`<script setup>` の `defineOptions({ name })` があるならそちらも一致すること
- ディレクトリ内で命名スタイルが混在している → 違反

検出方法:
1. 各層のファイル名パターンを集計
2. 多数派のスタイルを検出し、少数派を違反として報告
3. 単複数の統一（`Button/index.tsx` vs `buttons.tsx` の混在）も検出

### 2. 深い prop drilling（🟠 Important）

props が 3 段以上バケツリレーされている場合、context / provide-inject / 状態管理ストアの導入を検討する。

検出方法:
1. `pages` から `organisms` → `molecules` → `atoms` へと同名 prop が渡されるチェーンを追跡
2. 3 段以上を Important、4 段以上を Critical とする（React の Context API / Vue の provide-inject / Zustand / Pinia のような選択肢を提案）
3. atoms が直接受け取るべきスタイル系 prop（`variant`, `size` 等）は例外扱い

### 3. Composition パターン（🟡 Suggestion）

- **React**: 巨大な `switch` や `if` 分岐で子コンポーネントを出し分けている場合、`children` を渡す composition パターンを提案
- **Vue**: named slot ではなく巨大な props で分岐している場合、slot ベースの設計を提案
- **共通**: prop の数が 8 個以上のコンポーネントは分割を検討

### 4. 単一責務違反（🟠 Important）

1 ファイルに複数のコンポーネント export がある場合:
- 同じ層のヘルパーとしての小さなコンポーネント（10 行未満）は許容
- 独立して再利用可能な複数コンポーネントは別ファイルに分割すべき

### 5. データ取得の層違反（🟠 Important）

- atoms / molecules で `fetch`, `useSWR`, `useQuery`, `$fetch`, `useFetch`, `useAsyncData` などを呼んでいる → データ取得は organisms 以上に置くべき
- Next.js の Server Component 内でも同じ原則を適用（atoms/molecules は presentational に留める）

### 6. スタイル記述の一貫性（🟢 Minor）

同じ層内で以下が混在していないか:
- Tailwind vs CSS Modules vs styled-components vs UnoCSS
- Vue の `<style scoped>` vs グローバル CSS vs Tailwind

混在は必ずしも悪ではないが、Minor として指摘し、プロジェクト方針の明文化を提案する。
