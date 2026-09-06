# fixtures — storageState と per-test Factory

## storageState 事前生成

UI ログインを全テストから消す。`globalSetup` で全テストユーザーのセッションを作り、JSON に保存する。

```ts
// e2e/global-setup.ts
import { chromium, type FullConfig } from "@playwright/test";

const ROLES = ["admin", "approver", "editor", "viewer"] as const;
const ACCOUNTS_PER_ROLE = 5; // worker 間でアカウントを取り合わないよう複数用意する

export const storageStatePath = (role: string, index = 0) =>
  `.auth/${role}-${index}.json`;

export default async function globalSetup(config: FullConfig) {
  const browser = await chromium.launch();
  for (const role of ROLES) {
    for (let i = 0; i < ACCOUNTS_PER_ROLE; i++) {
      const context = await browser.newContext();
      const page = await context.newPage();
      await login(page, role, i);            // UI でも API でもよい
      await context.storageState({ path: storageStatePath(role, i) });
      await context.close();
    }
  }
  await browser.close();
}
```

```ts
// spec 側
test.use({ storageState: storageStatePath("admin") });
```

**ロールごとに複数アカウントを用意する理由**: 同一アカウントに複数 worker が同時ログインすると、セッション失効・排他ロック・「同時編集中」判定で干渉する。worker index からアカウントを選ぶ。

```ts
test.use({ storageState: ({}, use, testInfo) =>
  use(storageStatePath("admin", testInfo.workerIndex % ACCOUNTS_PER_ROLE)) });
```

`.auth/` は `.gitignore` に入れる。

## per-test Factory + teardown

テストごとに専用データを作り、終了時に派生レコード・ファイルまで回収する。**これが `fullyParallel: true` の前提条件。**

```ts
// e2e/features/document/fixtures.ts
export const test = base.extend<{ documentFactory: DocumentFactory }>({
  documentFactory: [
    async ({}, use) => {
      const admin = createAdminClient();          // service role / 管理接続
      const factory = createDocumentFactory(admin);
      await use(factory);
      await factory.teardown();                   // 派生レコード + ストレージまで一括回収
    },
    { scope: "test" },                            // worker ではなく test スコープ
  ],
});
```

```ts
// e2e/features/document/factories/document.ts
export function createDocumentFactory(admin: AdminClient) {
  const created: Array<{ table: string; id: string }> = [];
  const uploaded: string[] = [];

  return {
    async create(overrides: Partial<Document> = {}) {
      const doc = await admin.insert("documents", {
        title: `E2E-${randomUUID()}`,             // 一意な名前で他テストと衝突させない
        status: "draft",
        ...overrides,
      });
      created.push({ table: "documents", id: doc.id });
      return doc;
    },

    async attachFile(documentId: string, path: string) {
      const key = `e2e/${randomUUID()}`;
      await admin.upload(key, path);
      uploaded.push(key);
      created.push({ table: "attachments", id: (await admin.insert("attachments", { documentId, key })).id });
      return key;
    },

    async teardown() {
      for (const { table, id } of created.reverse()) {  // FK 順に逆順で削除
        await admin.delete(table, id);
      }
      await admin.removeFiles(uploaded);
    },
  };
}
```

**原則**

- 生成は必ず Factory 経由。spec 内で直接 INSERT しない
- 名前・キーは必ず一意化（`randomUUID()`）。固定値は並列で衝突する
- teardown は生成の逆順（FK 制約）
- 生成物は DB 行だけでなく、ストレージ・キュー・外部サービス上の副産物も回収する
- テストが落ちても teardown が走るよう、fixture の `use()` の後に置く（`try/finally` 相当）

## バックエンド別の admin client

| スタック | 管理接続 |
|---|---|
| Supabase | `createClient(url, SERVICE_ROLE_KEY)` — RLS を迂回して直接 INSERT |
| Prisma + Postgres | テスト用 `PrismaClient`（アプリとは別の接続文字列） |
| REST API のみ | 管理者トークンで内部 API を叩く（UI 操作より桁違いに速い） |

UI 操作でテストデータを作らない。準備に UI を使うと、その準備自体が flaky 源になり、実行時間も跳ね上がる。

## ローカルスタックの並列耐性

並列 worker が同時に叩くと、デフォルト設定のミドルウェアが先に音を上げる。症状が出たら疑う。

| 症状 | 原因 | 対処 |
|---|---|---|
| 504 / タイムアウト多発 | DB コネクションプール枯渇（PostgREST の既定は 10） | `PGRST_DB_POOL=30` 等に増やす |
| 即時 502 が散発 | リバースプロキシの keep-alive 再利用レース（上流が先に idle 接続を閉じる） | プロキシ側の idle timeout を上流より短くする。それでも出るなら接続再利用自体を無効化（`KONG_UPSTREAM_KEEPALIVE_MAX_REQUESTS=1`） |
| 日本語が豆腐（□）になる | CJK フォント未インストール | CI に `fonts-noto-cjk` を入れる |

502/504 をテストのリトライで吸収しない。インフラ側で原因を消す。
