# アーキテクチャ — レイヤー構成と project 分割

## レイヤー構成

```
spec → fixture → pages(POM) / helpers → repositories / precheckers / schemas → selectors / types
```

依存は左から右への一方向のみ。逆流したら設計ミス。

```
e2e/
├── playwright.config.ts
├── global-setup.ts          # storageState 事前生成
├── specs/
│   └── document/
│       ├── approve.spec.ts
│       └── bulk-import.spec.ts   # @heavy
├── fixtures/
│   ├── index.ts             # test.extend でまとめる
│   └── factories/           # per-test データ生成 + teardown
├── pages/                   # Page Object（Locator・操作・待機を閉じ込める）
├── repositories/            # DB 検証（SELECT のみ。INSERT/UPDATE を書かない）
├── precheckers/             # 前提データ検証（zod）
├── schemas/                 # zod schema
├── selectors/               # data-testid 定数
└── types/
```

**各層の禁止事項**

| 層 | 禁止 |
|---|---|
| `specs/` | `page.locator(...)` の直接呼び出し、生の testid 文字列 |
| `pages/` | DB アクセス、テストデータ生成 |
| `repositories/` | INSERT / UPDATE / DELETE（生成は Factory の責務） |
| `selectors/` | 定数以外のロジック |

## selectors の集約

```ts
// selectors/document.ts
export const documentSelectors = {
  approveButton: "document-approve-button",
  statusBadge: "document-status-badge",
  effectiveDate: "document-effective-date",
} as const;
```

```ts
// pages/document-view.ts
export class DocumentViewPage {
  readonly approveButton: Locator;

  constructor(private readonly page: Page) {
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

```ts
// playwright.config.ts
function lightProject(feature: string, testMatch: string, ciWorkers = 5): Project {
  return {
    name: `light-${feature}`,
    testMatch,
    grepInvert: /@heavy/,
    workers: process.env.CI ? ciWorkers : 4,
    fullyParallel: true,
    timeout: 60_000,
    use: { ...devices["Desktop Chrome"] },
  };
}

function heavyProject(feature: string, testMatch: string): Project {
  return {
    name: `heavy-${feature}`,
    testMatch,
    grep: /@heavy/,
    workers: 3,
    fullyParallel: false,   // 重いテストは並列で殴らない
    timeout: 180_000,
    use: { ...devices["Desktop Chrome"] },
  };
}

export default defineConfig({
  testDir: "./e2e/specs",
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
    lightProject("document", "**/document/**"),
    heavyProject("document", "**/document/**"),
    lightProject("user", "**/user/**"),
    heavyProject("user", "**/user/**"),
  ],
});
```

release 軸を使う場合は `light-${release}-${feature}` のように名前とディレクトリ（`specs/r140/document/`）を対応させる。

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
