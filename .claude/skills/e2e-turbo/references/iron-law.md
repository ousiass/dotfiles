# Iron Law — flaky を構造的に潰す規約

並列度を上げると flaky は指数的に増える。以下は例外なく守る。spec / POM を書き終えたら、各条をセルフチェックリストとして1件ずつ通すこと。

## Law #1: 固定時間待機の禁止

```ts
// NG
await page.waitForTimeout(2000);

// OK
await this.requestButton.waitFor({ state: "hidden", timeout: 30_000 });
```

「待てば通る」は「待たなければ落ちる」と同義。状態を待つ。

## Law #2: retries=0 で運用する

```ts
retries: 0,
```

リトライは非冪等操作（作成・承認・削除）を二重実行する。flaky を隠すのではなく、落ちた原因を直す。

## Law #3: spec から locator を直接引かない

```ts
// NG: spec 内
await page.locator('[data-testid="approve-button"]').click();

// OK: spec 内
await documentView.approve();
```

Locator・操作・待機は Page Object に閉じ込める。testid 文字列は `selectors/` の定数に集約する。

## Law #4: 同期 read + 静的 assert の禁止

```ts
// NG: snapshot 時点で未確定でも偶然通る／偶然落ちる
const text = await locator.innerText();
expect(text).toContain("承認済み");

// OK: auto-wait matcher で値の settle を待つ
await expect(locator).toContainText("承認済み");
```

`innerText()` / `textContent()` / `getAttribute()` の戻り値を `expect()` に渡していたら違反。

## Law #5: 不在判定の前に陽性ランドマークを待つ

```ts
// NG: 描画前の DOM 0 個で誤通過する
await expect(editButton).not.toBeVisible();

// OK: 「画面が確かに描画された」証拠を先に立ててから不在を確認
await documentView.expectStatus("承認済み");
await expect(documentView.effectiveDate).toBeVisible();
await expect(documentView.editButton).toHaveCount(0);
```

`not.toBeVisible()` / `toHaveCount(0)` を単独で書いたら違反。

## Law #6: Silent Success は busy の「出現 → 消滅」を2段で待つ

完了トーストが出ない操作（ダウンロード・自動保存・バックグラウンド処理）で使う。

```ts
await busyIndicator.waitFor({ state: "visible" }); // 出現
await busyIndicator.waitFor({ state: "hidden" });  // 消滅
```

消滅だけ待つと「まだ始まっていない」状態を通過してしまう。

## Law #7: 再取得後に表示が変わらないレースは通信を待つ

ソート・フィルタ・ページングなど「API 再取得 → 同じ見た目で再描画」される操作は、DOM では完了を判定できない。

```ts
async sortByColumn(column: SortColumn): Promise<void> {
  await this.runAndWaitForRpc("get_paginated_templates_with_sort", () =>
    this.sortButton(column).click()
  );
}
```

```ts
// POM 基底クラスに置くヘルパ
protected async runAndWaitForRpc(endpoint: string, action: () => Promise<void>) {
  const response = this.page.waitForResponse(
    (r) => r.url().includes(endpoint) && r.ok()
  );
  await action();
  await response;
}
```

## Law #8: 前提データは precheck で検証する

テスト本体が落ちたのか、前提データが壊れていたのかを区別できるようにする。

```ts
// e2e/features/document/prechecks.ts
const schema = z.object({ id: z.string().uuid(), status: z.literal("draft") });

export function precheckDocument(row: unknown) {
  const result = schema.safeParse(row);
  if (!result.success) {
    throw new Error(`[precheck] document 前提データ不正: ${result.error.message}`);
  }
  return result.data;
}
```

`[precheck]` プレフィックスで失敗を分類する。

## Law #9: アニメーション完了まで待ってから操作する

フェードイン中の要素をクリックすると、座標がずれるうえ動画にフレームが残らず調査不能になる。

```ts
await expect(this.dialog).toBeVisible();
await this.dialog.waitFor({ state: "visible" });
await expect(this.dialog).toHaveCSS("opacity", "1");
```

## Law #10: 証跡を常時記録する

```ts
use: {
  video: "on",
  screenshot: "only-on-failure",
  trace: "retain-on-failure",
}
```

`video: "on"` は全テストで記録する。失敗時のみでは、並列環境で「なぜその瞬間そうなったか」が追えない。

## セルフチェックリスト

spec / POM を書いたら、以下を grep で機械的に確認する。

```bash
rg 'waitForTimeout' e2e/                        # Law #1: 0 件であること
rg 'page\.locator' e2e/features/*/specs/        # Law #3: 0 件であること
rg 'await (locator|this\.\w+)\.(innerText|textContent)\(\)' e2e/  # Law #4
rg 'not\.toBeVisible|toHaveCount\(0\)' e2e/     # Law #5: 前段に陽性 assert があるか目視
```
