# 変換規則 — 録画から Iron Law 準拠のテストへ

録画は**下書き**であり、そのまま spec にはしない。以下の規則で翻訳する。

## 1. 画面の目印を抽出する

### codegen 出力（`.raw.ts`）

| 録画の出力 | 変換先 | 対応 |
|---|---|---|
| `page.getByTestId('document-approve-button')` | `selectors.ts` の定数 + POM の Locator | そのまま使える |
| `page.getByRole('button', { name: '承認' })` | 同上 | **目印が無い**。アプリ側に `data-testid` を付与してから変換 |
| `page.locator('.btn-primary')` | 同上 | 同上。CSS クラス依存は実装変更で壊れるので残さない |
| `page.getByText('承認済み')` | assert 側で使う | 表示確認なら `toContainText` に回す |

### Chrome Recorder 出力（`.json`）

`steps[].selectors` は候補が配列で入る。優先順位は以下。

1. `[data-testid=...]` を含むもの → そのまま使う
2. `aria/...` → 意味は正しいが壊れやすい。`data-testid` を付与して置き換える
3. `#id` / CSS / `xpath/...` → 必ず `data-testid` に置き換える

`steps[].type` の対応: `navigate` → `goto()`、`click` → `click()`、`change` → `fill()`、`keyDown`(Enter) → `press('Enter')`、`waitForElement` → `waitFor({ state })`、`setViewport` → 破棄（config の設定を使う）。

## 2. data-testid をアプリに付与する

目印が無い箇所は、**アプリのコードに `data-testid` を追加する**のが正しい対応。セレクタを工夫して逃げない。

```vue
<!-- before -->
<button class="btn-primary" @click="approve">承認</button>
<!-- after -->
<button class="btn-primary" data-testid="document-approve-button" @click="approve">承認</button>
```

命名は `<feature>-<対象>-<種別>` で既存に揃える。追加したファイルは PR 本文に一覧で書く。

外部ライブラリ由来で付与できない要素のみ、`getByRole` を POM 内に閉じ込めて許容する（spec には出さない）。

## 3. 操作を Page Object にまとめる

録画は「クリック、入力、クリック…」の平坦な列で出てくる。**意味のまとまりで切って**メソッド化する。切り方はテスターの言葉（フェーズ2の回答）に合わせる。

```ts
// _recordings/approve.raw.ts（録画そのまま・これは spec にしない）
await page.getByTestId('document-row-0').click();
await page.getByTestId('document-approve-button').click();
await page.getByTestId('confirm-dialog-ok').click();
```

```ts
// features/document/pages/document-list.ts
async openFirstDocument(): Promise<DocumentViewPage> {
  await this.rowAt(0).click();
  const view = new DocumentViewPage(this.page);
  await view.waitForLoaded();
  return view;
}

// features/document/pages/document-view.ts
async approve(): Promise<void> {
  await this.approveButton.click();
  await this.confirmDialog.waitFor({ state: 'visible' });   // Law #9: 表示を待ってから押す
  await this.confirmOkButton.click();
  await this.confirmDialog.waitFor({ state: 'hidden' });    // Law #6: 消滅まで待つ
}
```

```ts
// features/document/specs/approve.spec.ts
test('承認待ちの文書を承認できる', async ({ page, documentFactory }) => {
  const doc = await documentFactory.create({ status: 'pending' });
  const list = await DocumentListPage.goto(page);
  const view = await list.openFirstDocument();
  await view.approve();
  await view.expectStatus('承認済み');
});
```

spec がテスターの説明文と同じ順に読めれば成功。

## 4. HAR から待機を埋める（Law #7）

録画中に発生した通信を抽出し、**押しても見た目が変わらない操作**に `runAndWaitForRpc` を当てる。

```bash
jq -r '.log.entries[]
  | select(.request.method != "OPTIONS")
  | "\(.request.method) \(.request.url) \(.time)ms"' e2e/_recordings/<name>.har \
  | grep -v '\.(js|css|png|svg|woff2)'
```

判定基準:

- 操作直後に XHR/fetch が飛び、**その応答で一覧や表示が差し替わる** → `runAndWaitForRpc` 対象
- ソート・フィルタ・ページング・検索・再読込ボタンは、ほぼ確実に対象
- 応答時間（`.time`）が大きいものは `@heavy` 判定の材料にする

経路B（Chrome Recorder）では HAR が無い。上記に当たる操作が含まれる場合は、アプリのコードから該当エンドポイントを特定して手動で入れる。

## 5. 確認したいことを assert に翻訳する

フェーズ2 の回答を、Iron Law に沿った形に落とす。**録画に写っていた文言を勝手に全部 assert にしない**（意図しない箇所で落ちるテストになる）。

| テスターの回答 | 変換 |
|---|---|
| 「ステータスが『承認済み』になる」 | `await expect(statusBadge).toContainText('承認済み')`（Law #4: 同期 read を挟まない） |
| 「完了メッセージが出る」 | `await expect(toast).toBeVisible()` |
| 「編集ボタンが消えている」 | **陽性ランドマークを先に**待ってから `toHaveCount(0)`（Law #5） |
| 「エラーが出ない」 | 単独では書かない。「正常終了の証拠」を陽性で確認する形に置き換える |
| 「ファイルがダウンロードされる」 | `page.waitForEvent('download')` + 保存内容の確認。または busy の出現→消滅の2段待ち（Law #6） |

## 6. 前提データを Factory にする

テスターは既存データを触って録画しているので、録画からは前提データが取れない。フェーズ2の回答（例:「承認待ちの文書が1件」）を `factories/` の生成コードに翻訳する。

- 既存 factory があれば再利用する
- 無ければ、アプリのスキーマ／マイグレーションを読んで新規作成する
- 生成物は必ず teardown で回収する。名前は `randomUUID()` で一意化する（並列実行のため）

**録画に写っていた実データの ID を spec に直書きしない。** 他の環境で動かなくなり、並列実行でも衝突する。

## 7. 変換後チェック

```bash
rg 'waitForTimeout' e2e/                        # 0 件
rg 'page\.locator' e2e/features/*/specs/        # 0 件
rg '_recordings' e2e/features/                  # 0 件（録画への参照が残っていないか）
git status --porcelain e2e/_recordings          # 追跡されていないこと
```
