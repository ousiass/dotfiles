# Next.js 固有チェック

Phase 1 でフレームワークが **Next.js** と判定された場合のみ実行する。

## チェック対象

- `app/**/*.{tsx,jsx}`（App Router）
- `pages/**/*.{tsx,jsx}`（Pages Router）
- `src/components/**/*.{tsx,jsx}` または `components/**/*.{tsx,jsx}`

## チェック項目

### 1. Server Component から Client-only モジュールを呼ぶ（🔴 Critical）

App Router では既定で Server Component。ブラウザ専用 API や `useState`/`useEffect` などの Client hook を Server Component 内で使うとビルドエラーになる。

検出方法:
1. ファイル冒頭に `"use client"` があるか判定
2. `"use client"` 未指定のファイルで以下を使用していれば違反として報告:
   - React hooks: `useState`, `useEffect`, `useReducer`, `useContext`, `useRef`, `useLayoutEffect`
   - ブラウザ API: `window`, `document`, `localStorage`, `sessionStorage`
   - `next/navigation` の `useRouter`, `usePathname`, `useSearchParams`
   - イベントハンドラの直接指定（`onClick={...}` などトップレベル）

### 2. Client Component から Server 専用モジュール参照（🔴 Critical）

`"use client"` 付きファイルから以下を import すると実行時エラー。

- `server-only` パッケージ
- `next/headers`（`cookies`, `headers`）
- `next/server`
- Node.js 専用モジュール（`fs`, `path`, `child_process` など）

検出方法:
1. `"use client"` 付きファイルの import 文を全て解析
2. 上記に該当する import を違反として報告

### 3. 'use client' の過剰付与（🟠 Important）

以下の場合は `"use client"` が不要である可能性が高い:
- ファイル内で Client hook / ブラウザ API / イベントハンドラを一切使っていない
- 純粋な presentational コンポーネント（props を受け取って JSX を返すだけ）

検出方法:
1. `"use client"` 付きファイルを列挙
2. 各ファイルで Client 専用 API の使用有無を確認
3. 未使用の場合は指摘（バンドルサイズ増加のため）

### 4. データ取得の配置（🟠 Important）

- App Router で `fetch` / DB 呼び出しは Server Component 側に置くのが望ましい
- Client Component 内での `fetch` は `useEffect` + loading state を伴い、パフォーマンス劣化しがち
- `atoms` / `molecules` は Server / Client どちらでも presentational に留める（check-quality.md 5 と統合して判定）

### 5. Atomic pages とフレームワーク pages の混同（🟠 Important）

- Atomic の `pages/` レイヤーが `app/` や root の `pages/`（Pages Router）と同じディレクトリに置かれていないか
- 混同がある場合は `components/pages/`（もしくは別名）への移動を提案

### 6. `next/link` / `next/image` の未使用（🟡 Suggestion）

- atoms 層で `<a href>` を使っている場合、内部リンクなら `next/link` の使用を提案
- `<img>` タグを使っている場合、`next/image` の使用を提案（外部画像で `unoptimized` が必要な場合を除く）

### 7. App Router の Route Handler / Server Action 配置（🟡 Suggestion）

- `app/**/route.ts` や `"use server"` 関数が `components/` 配下にある → `app/api/**` や `actions/` 配下への移動を提案
