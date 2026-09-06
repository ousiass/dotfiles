# アーキテクチャ — レイヤー構成と project 分割

## レイヤー構成

```
spec → fixture → pages(POM) / helpers → repositories / precheckers / schemas → selectors / types
```

依存は左から右への一方向のみ。逆流したら設計ミス。

## ディレクトリ構成（feature 縦割り）

feature ごとに縦割りし、全 feature 共通のものだけ `shared/` に置く。

```
e2e/
├── playwright.config.ts
├── global-setup.ts               # storageState 事前生成
├── shared/
│   ├── admin-client.ts           # テストデータ生成用の管理接続
│   ├── base-page.ts              # POM 基底（runAndWaitForRpc 等の共通待機）
│   └── storage-state.ts          # storageStatePath / ロール定義
└── features/
    └── document/
        ├── specs/
        │   ├── approve.spec.ts
        │   └── bulk-import.spec.ts   # @heavy
        ├── pages/                    # Page Object（Locator・操作・待機を閉じ込める）
        │   ├── document-view.ts
        │   └── document-list.ts
        ├── factories/                # per-test データ生成 + teardown
        │   └── document.ts
        ├── repositories/             # DB 検証（SELECT のみ）
        │   └── document.ts
        ├── fixtures.ts               # test.extend でこの feature の fixture をまとめる
        ├── prechecks.ts              # 前提データ検証
        ├── schemas.ts                # zod schema
        ├── selectors.ts              # data-testid 定数
        └── types.ts
```

feature をまるごと追加・削除でき、1つの機能を触るときの行き来が `features/<name>/` の中で完結する。

**各層の禁止事項**

| 層 | 禁止 |
|---|---|
| `specs/` | `page.locator(...)` の直接呼び出し、生の testid 文字列 |
| `pages/` | DB アクセス、テストデータ生成 |
| `repositories/` | INSERT / UPDATE / DELETE（生成は Factory の責務） |
| `selectors.ts` | 定数以外のロジック |
| `shared/` | 特定 feature にしか使わないもの |

**feature を跨ぐとき**: 別 feature の POM を直接 import しない。共通で使う画面（ヘッダ、ログイン、共通ダイアログ）は `shared/pages/` に切り出す。

## linterly 対応

`max_lines_per_file: 300` / `max_lines_per_directory: 2000` を前提に設計する。

- **ディレクトリ集計は直下ファイルのみで再帰しない。** よって feature 縦割りは linterly と相性が良い。横割りの `pages/` に全 feature の POM を積むと単一ディレクトリで 2000 行に当たる
- **POM が 300 行を超えたら画面・セクション単位に割る**（`document-view.ts` → `document-view.ts` + `document-view-approval-panel.ts`）。1クラスに全 Locator を詰め込まない
- **spec が 300 行を超えたらシナリオ群で割る**（`approve.spec.ts` / `approve-reject.spec.ts`）。`@heavy` を含む spec は元々分けるので、そこが自然な分割線になる
- **`selectors.ts` が 300 行を超えたら `selectors/` ディレクトリに昇格**させる。他のフラットファイル（`schemas.ts` `prechecks.ts` `types.ts`）も同様
- `e2e/` を `.linterlyignore` に入れて逃げない。テストコードこそ肥大化する

## selectors の集約

```ts
// features/document/selectors.ts
export const documentSelectors = {
  approveButton: "document-approve-button",
  statusBadge: "document-status-badge",
  effectiveDate: "document-effective-date",
} as const;
```

```ts
// features/document/pages/document-view.ts
export class DocumentViewPage extends BasePage {
  readonly approveButton: Locator;

  constructor(page: Page) {
    super(page);
    this.approveButton = page.getByTestId(documentSelectors.approveButton);
  }

  async approve(): Promise<void> {
    await this.approveButton.click();
    await this.approveButton.waitFor({ state: "hidden", timeout: 30_000 });
  }

  async expectStatus(status: string): Promise<void> {
    await expect(this.page.getByTestId(documentSelectors.statusBadge)).toContainText(status);
  }
}
```

対象画面に `data-testid` が無ければアプリ側に付与する。CSS セレクタや文言でのロケートは、実装変更で壊れるので使わない。

## 3軸 project 分割

`load`（負荷プロファイル）× `release` × `feature` で project を切り、CI では project 単位で job を分ける。
feature 軸はディレクトリと一対一に対応させる（project 名から見るべき場所が決まる）。

```ts
// playwright.config.ts
function lightProject(feature: string, ciWorkers = 5): Project {
  return {
    name: `light-${feature}`,
    testMatch: `**/features/${feature}/specs/**`,
    grepInvert: /@heavy/,
    workers: process.env.CI ? ciWorkers : 4,
    fullyParallel: true,
    timeout: 60_000,
    use: { ...devices["Desktop Chrome"] },
  };
}

function heavyProject(feature: string): Project {
  return {
    name: `heavy-${feature}`,
    testMatch: `**/features/${feature}/specs/**`,
    grep: /@heavy/,
    workers: 3,
    fullyParallel: false,   // 重いテストは並列で殴らない
    timeout: 180_000,
    use: { ...devices["Desktop Chrome"] },
  };
}

export default defineConfig({
  testDir: "./e2e/features",
  globalSetup: "./e2e/global-setup.ts",
  retries: 0,
  reporter: [["html"], ["github"]],
  use: {
    baseURL: process.env.E2E_BASE_URL ?? "http://localhost:4173",
    video: "on",
    screenshot: "only-on-failure",
    trace: "retain-on-failure",
  },
  projects: [
    lightProject("document"), heavyProject("document"),
    lightProject("user"),     heavyProject("user"),
  ],
});
```

release 軸を使う場合は `features/document/specs/r140/` のように spec 側で切り、project 名を `light-r140-document` にして `testMatch` を合わせる。

## @heavy タグの付け方

以下のいずれかに当たるものは `@heavy` を付ける。

- 実行に 30 秒以上かかる
- 大量データの投入・一括処理・ファイル生成を伴う
- 外部プロセス（Edge Function、ワーカー、メール送信）を待つ

```ts
test("大量文書の一括インポート @heavy", async ({ page, documentFactory }) => { ... });
```

## workers の決め方

- ローカル: 物理コア数の半分から始める
- CI: `light` は `コア数 - 3` 程度、`heavy` は 3 固定
- 上げすぎると CPU 待ちでタイムアウトが増え、かえって遅くなる。`--repeat-each=3` が緑のままの上限を探る

CPU 飽和の判定は `/proc/pressure/cpu` の `full` avg10 を見る（0 に近ければ余裕、10 を超えたら worker 過剰）。
