---
name: e2e-turbo
description: Playwright E2E を並列前提で構築・追加し、全量数分で完走する爆速テスト基盤を作る
user-invocable: true
---

# e2e-turbo

E2E を「並列実行できる構造」から設計し、全量を数分で完走させる。既存プロジェクトを検出して、基盤が無ければ基盤から作り、あればその構造に沿ってテストだけ足す。

出典: https://zenn.dev/berry_blog/articles/39392e1da7ca71

## 前提条件

- Claude Code 環境
- Node.js / Bun 系プロジェクト（パッケージマネージャは **bun** を使う）
- ローカルでアプリとバックエンドを起動できること

## 引数

- **対象指定** (例: `/e2e-turbo 文書承認フロー`): テスト対象の機能・画面
- **引数なし**: フェーズ0 でヒアリングして確定

## 爆速化の4本柱

| 柱 | 効果 | 参照 |
|---|---|---|
| 3軸 project 分割 + 二段並列 | CI の wall-clock を分割数で割る | `references/architecture.md` |
| storageState 事前生成 | 全テストから UI ログインを消す | `references/fixtures.md` |
| per-test Factory + teardown | テスト間共有状態を構造的に禁止し `fullyParallel` を成立させる | `references/fixtures.md` |
| impact-map | PR では影響 spec のみ実行 | `references/impact-map.md` |

並列化は Iron Law（`references/iron-law.md`）とセットでのみ成立する。並列度だけ上げると flaky が爆発する。

## フェーズ0: 検出と初回ヒアリング

### 0-1: 現状検出

以下を調べ、「基盤あり／なし」を判定する:

- `playwright.config.*` / `e2e/` / `tests/e2e/` の有無と中身
- `package.json`（fw、スクリプト、`@playwright/test`）
- バックエンド: `supabase/`, `prisma/`, `docker-compose*.yml`, `.env*`
- 既存 CI: `.github/workflows/*.yml`
- 既存の POM / fixture / selectors 構造（あればその命名規約に従う）
- `.linterly.yml` の有無（あれば行数上限を分割基準に反映する）

**基盤ありの判定基準**: `playwright.config.*` が存在し、project 分割と fixture が既にある。
部分的（config はあるが単一 project、fixture 無し等）なら「不足分のみ補う」扱いにする。

### 0-2: まとめてヒアリング

`AskUserQuestion` で一度に聞く（最大4問）。**CI の扱いは必ず最初に聞く**。

1. **CI に追加するか**
   - GitHub Actions に matrix workflow を新規追加する
   - 既存 workflow にジョブとして組み込む
   - ローカル実行のみ（CI は追加しない）
2. **テスト対象スコープ**（引数で指定済みならスキップ）
3. **テストデータ戦略**
   - Factory で DB へ直接 INSERT（推奨・最速）
   - 既存 seed / fixture SQL を流用
   - アプリの API 経由で作成
4. **並列軸の粒度**
   - `light/heavy × feature`（推奨・多くのプロジェクトはこれで足りる）
   - `light/heavy × release × feature`（リリース単位で spec を分けている場合）
   - `light/heavy` のみ（spec 数が少ない場合）

CI を「追加しない」と答えた場合も、config の project 分割は行う（ローカルでも並列は効く）。

以降は完了まで割り込まない。追加の不明点が出たら、その時点でまとめて1回だけ聞く。

## フェーズ1: 基盤構築

基盤なし／不足のときのみ実行する。`references/architecture.md` と `references/fixtures.md` を読んでから着手する。

1. `bun add -d @playwright/test` / `bunx playwright install --with-deps chromium`
2. ディレクトリ構成を作る（`references/architecture.md` の feature 縦割り構成）
3. `playwright.config.ts` に project 生成関数（`lightProject` / `heavyProject`）を書く
4. `globalSetup` で storageState を事前生成する
5. `fixtures/` に Factory bundle fixture（teardown 込み）を置く
6. CI を作る場合のみ `references/ci.md` に従って workflow を追加する
7. impact-map を採用する場合のみ `references/impact-map.md` に従う

**必須設定**（理由は architecture.md）:

```ts
retries: 0,          // 非冪等操作のリトライを構造的に禁止
video: "on",         // 失敗時の証跡を必ず残す
fullyParallel: true, // light project のみ
```

## フェーズ2: テスト追加

**spec / POM を書く前に `references/iron-law.md` を必ず Read する。** 読まずに書かない。

対象 feature を決め、`e2e/features/<feature>/` の中で完結させる。無ければ feature ディレクトリごと作る。

1. 対象画面の `data-testid` を調査する。無ければアプリ側に付与する（付与も本スキルの作業範囲）
2. `selectors.ts` に testid 定数を追加
3. `pages/` に Page Object を追加（Locator・操作・待機を全てここに閉じ込める）
4. DB 検証が要るなら `repositories/`（SELECT のみ）を追加
5. 前提データが要るなら `factories/` に生成 + teardown を、検証が要るなら `prechecks.ts` + `schemas.ts` を追加
6. `specs/` に spec を書く。重いものには `@heavy` タグを付ける
7. 新しい feature なら `playwright.config.ts` に `lightProject` / `heavyProject` を追加する
8. Iron Law のセルフチェックリストを1件ずつ通す

**spec から `page.locator(...)` を直接呼ばない。** 違反したら POM に移す。

## フェーズ3: 検証とコミット

1. 追加した spec を単体実行 → green
2. **同一 project を並列で3回連続実行**して flaky を検出（`bunx playwright test --project=... --repeat-each=3`）
3. 落ちたら Iron Law に照らして原因を特定する。`waitForTimeout` や retry で誤魔化さない
4. lint / format / `bunx linterly check e2e/`（設定があれば）
5. CLAUDE.md の規約に従いコミット（`test: ...` / `feat: ...`）

## ルール

- **`page.waitForTimeout` は書かない。** state-based wait のみ
- **`retries` を上げて flaky を隠さない。** 原因を直す
- テスト間で状態を共有しない。共有したくなったら Factory の設計を見直す
- 既存の命名規約・ディレクトリ構造がある場合はそれを尊重し、置換ではなく拡張する
- **linterly の 300行/ファイル・2000行/ディレクトリを守る。** `e2e/` を `.linterlyignore` に入れて逃げない。分割基準は `references/architecture.md`
- パッケージマネージャは bun に固定（`npm` / `yarn` / `pnpm` / `npx` を使わない）
- 質問は `AskUserQuestion` で選択式にする。テキストだけで聞かない
- 進捗は TaskCreate / TaskUpdate で管理する

## references

| ファイル | 読むタイミング |
|---|---|
| `references/architecture.md` | 基盤構築時（config・レイヤー構成） |
| `references/fixtures.md` | 基盤構築時（storageState・Factory・teardown） |
| `references/iron-law.md` | **spec / POM を書く前に必ず** |
| `references/ci.md` | CI を追加すると回答した場合 |
| `references/impact-map.md` | impact-map を採用した場合 |
