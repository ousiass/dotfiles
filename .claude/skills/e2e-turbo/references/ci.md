# CI — GitHub Actions で project 単位に matrix 分割

フェーズ0 で「CI に追加する」と回答した場合のみ実施する。

## 基本構成

project 単位で job を分け、各 job の中で Playwright workers がさらに並列に走る（二段の並列化）。

```yaml
name: e2e

on:
  pull_request:
  push:
    branches: [main]

concurrency:
  group: e2e-${{ github.ref }}
  cancel-in-progress: true    # 同一 ref の古いランを止める

jobs:
  e2e:
    runs-on: ubuntu-latest    # 8core Larger Runner が使えるなら ubuntu-24.04-8core
    strategy:
      fail-fast: false        # 1 project の失敗で他を巻き込まない
      matrix:
        project:
          - light-document
          - heavy-document
          - light-user
          - heavy-user
    steps:
      - uses: actions/checkout@v4

      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile

      - name: Playwright ブラウザのキャッシュ
        id: pw-cache
        uses: actions/cache@v4
        with:
          path: ~/.cache/ms-playwright
          key: pw-${{ runner.os }}-${{ hashFiles('bun.lock') }}

      - if: steps.pw-cache.outputs.cache-hit != 'true'
        run: bunx playwright install --with-deps chromium

      - name: CJK フォント
        run: sudo apt-get install -y fonts-noto-cjk

      - name: バックエンド起動
        run: |
          # 例: supabase start / docker compose up -d / prisma migrate deploy
          bun run e2e:backend:up

      - name: アプリのビルドと起動
        run: |
          bun run build
          bun run preview &
          bunx wait-on http://localhost:4173

      - run: bunx playwright test --project=${{ matrix.project }}

      - if: always()
        uses: actions/upload-artifact@v4
        with:
          name: report-${{ matrix.project }}
          path: playwright-report/
          retention-days: 7
```

## 押さえどころ

- **`fail-fast: false`**: 他 project の結果も見たいので必ず切る
- **`concurrency` + `cancel-in-progress`**: matrix で job 数が増えるため、古いランの停止は必須
- **ツール CLI のバージョンピン留め**: matrix 同時実行で GitHub Releases API の rate limit に当たる。`supabase` CLI などは `version:` を明示する
- **Playwright ブラウザキャッシュ**: `~/.cache/ms-playwright` をキャッシュしないと毎 job で数十秒〜数分持っていかれる
- **毎回まっさらな環境で本物のフルスタックを立てる**: モックに寄せると爆速にはなるが、E2E である意味が消える
- **`ubuntu-latest`（2core）ではワーカー数を絞る**: `light` は 2〜3。8core Larger Runner が使えるなら 5 前後まで上げられる

## workflow を分割するか統合するか

| 状況 | 判断 |
|---|---|
| project が 4 つ以下 | 単一 workflow の matrix で十分 |
| project が多く、実行時間に大きな差がある | 重い project を別 workflow に切り、PR チェック必須から外す選択肢もある |
| PR ごとの実行時間を切り詰めたい | `references/impact-map.md` の影響範囲実行を併用する |

## 失敗調査

`video: "on"` で記録した動画は HTML レポートに添付される。失敗時は `playwright-report` artifact をダウンロードし、動画とトレースで再現する。CI ログだけで原因を推測しない。
