# Nuxt 固有チェック

Phase 1 でフレームワークが **Nuxt v3** または **Nuxt v4** と判定された場合のみ実行する。

## v3 と v4 の差異

- **Nuxt v3**: 既定の srcDir はプロジェクトルート。`components/`, `pages/`, `layouts/`, `composables/` はルート直下
- **Nuxt v4**: 既定の srcDir が `app/` に変更。`app/components/`, `app/pages/`, `app/layouts/`, `app/composables/` を使う（`server/`, `public/`, `content/`, `nuxt.config.*` は引き続きルート）
- 検出は Phase 1 の判定を優先。プロジェクト内で `app/` 配下と ルート直下が両方存在する場合は移行途中の可能性があるため 🟠 Important として報告

以降の記述で `<src>/` と書いた場合、v3 なら空、v4 なら `app/` を指す。

## チェック対象

- `<src>/components/**/*.vue`
- `<src>/pages/**/*.vue`, `<src>/layouts/**/*.vue`
- `<src>/composables/**/*.{ts,js}`
- `nuxt.config.{ts,js}`

## チェック項目

### 1. auto-import 想定外の階層（🟠 Important）

Nuxt v3 は `components/` 配下を auto-import する。ネストしたディレクトリは前置詞付きコンポーネント名になる（例: `components/atoms/Button.vue` → `<AtomsButton />`）。

- `nuxt.config.ts` の `components` 設定を読み、`pathPrefix` の指定を確認
- Atomic レイヤーを前置詞として使いたくない場合、`pathPrefix: false` の設定を推奨として提示
- 設定と実際の使用（`<Button />` vs `<AtomsButton />`）が食い違うファイルを違反として報告

### 2. composables/ に置くべきロジックが components/ にある（🟠 Important）

以下は composables として抽出すべき:
- 複数コンポーネントで再利用されるリアクティブなロジック
- `useFetch`, `useAsyncData` のラッパー
- グローバル state（`useState` のラッパー）
- ライフサイクル管理を含むロジック（`onMounted` + イベントリスナー登録など）

検出方法:
1. 各 `.vue` ファイルの `<script setup>` を解析
2. 同じ `useFetch(...)` 呼び出しが 2 ファイル以上で重複していれば違反
3. 30 行以上のロジック関数が定義されていれば composables への抽出を提案

### 3. Atomic pages と Nuxt pages の衝突（🔴 Critical / 🟠 Important）

- `<src>/pages/` は Nuxt のファイルベースルーティング用
- Atomic の `pages/` レイヤーが同じ場所に存在すると、意図しないルートが生成される
- Atomic pages は `<src>/pages/` ではなく `<src>/components/pages/` に置くべき（v3 なら `components/pages/`、v4 なら `app/components/pages/`）

検出方法:
1. `<src>/pages/` 直下のファイルを列挙
2. Nuxt ルーティングに使われないコンポーネント（サブディレクトリで `.vue` 拡張子でない、または Atomic pages 命名パターン）が混在していれば違反として報告
3. `<src>/components/pages/` に相当するディレクトリがあり、そこにも Atomic pages がある場合は Nuxt ルーティング側の `pages/` から Atomic レイヤーを排除するよう提案

### 4. layouts/ と Atomic layout/ の混同（🟠 Important）

- Nuxt の `<src>/layouts/` はレイアウトファイル用の予約ディレクトリ
- Atomic の `layout/` は `<src>/components/layout/` に置くべき
- `<src>/layouts/` に Atomic 用の共通レイアウトコンポーネントが混ざっていれば違反

### 4-b. v3 → v4 移行途中の混在（🟠 Important / Nuxt v4 のみ）

- ルートレベルの `components/`, `pages/`, `layouts/`, `composables/` と `app/` 配下が両方存在する
- ファイルが二重定義されている場合、Nuxt v4 では `app/` 側が優先されるが、意図しないバージョンが読まれる恐れがある
- 移行完了後はルート側を削除するか、v3 互換のため `srcDir: '.'` を明示するよう提案

### 5. `<script>` (Options API) と `<script setup>` の混在（🟡 Suggestion）

同じ層内で Options API と Composition API が混在している場合、プロジェクトで方針を統一するよう提案する。

### 6. defineProps の型定義漏れ（🟡 Suggestion）

`defineProps` に型パラメータまたはランタイム定義がないコンポーネントを報告する。TypeScript プロジェクトの場合は Important、JS プロジェクトの場合は Suggestion。

### 7. useRuntimeConfig / useState のスコープ違反（🟠 Important）

- atoms / molecules が `useRuntimeConfig` を直接呼び出している → organisms 以上に集約すべき
- グローバル `useState('key')` を atoms / molecules から使用 → prop 経由で受け取るべき
