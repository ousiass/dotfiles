# CI ベースラインと判定手順

## 必須／推奨ジョブ

「PR で自動的に走り、落ちたらマージできない」状態になって初めて充足とみなす。

| ジョブ | 区分 | 欠落時 | 備考 |
|---|---|---|---|
| lint | 必須 | 🟠 | ESLint / Biome / golangci-lint / ruff |
| format check | 必須 | 🟡 | `--check` で差分検出（自動整形コミットはしない） |
| typecheck | 必須 | 🟠 | `tsc --noEmit` / `mypy` / `go vet` |
| build | 必須 | 🟠 | 本番ビルドが通るか |
| unit test | 必須 | 🔴 | |
| integration test | 必須 | 🔴 | DB・API を持つプロジェクトのみ |
| E2E | 推奨 | 🟠 | 画面があるプロジェクト。`/e2e-turbo` の matrix workflow を推奨 |
| coverage gate | 必須 | 🔴 | 閾値未達で fail すること。出力だけは不可 |
| diff coverage | 推奨 | 🟠 | 変更行の被覆 |
| 依存監査 | 推奨 | 🟡 | `bun audit` / `govulncheck` / `pip-audit` / Dependabot |
| secret scan | 推奨 | 🟡 | gitleaks / GitHub secret scanning |
| migration check | 条件付 | 🟠 | DB マイグレーションがある場合、適用と rollback の検証 |

## トリガの判定

| トリガ | 意味 |
|---|---|
| `pull_request` | ✅ ゲートとして機能しうる |
| `push: [main]` のみ | ❌ マージ後にしか気づけない → 🔴 |
| `schedule` / `workflow_dispatch` のみ | ❌ PR を守らない → 🟠 |
| `pull_request` + `paths` フィルタ | ⚠️ 対象外の変更で走らない。フィルタ内容を精査する |

## テストが実質無効化されるアンチパターン

```yaml
continue-on-error: true          # 落ちても success になる
run: bun test || true            # 終了コードを握り潰す
run: bun test --passWithNoTests  # テスト0件でも緑（テスト消失を検知できない）
if: false                        # 恒久的に無効
timeout-minutes 未設定           # ハングで詰まる
run: bun test --coverage         # 出力するだけで閾値判定が無い
jobs.<x>.if: github.actor != ... # 特定条件で素通り
```

Grep で一括検出する:
```bash
grep -rnE "continue-on-error|\|\| true|if: false|passWithNoTests" .github/workflows/
```

## required status checks の確認

```bash
# 1. classic branch protection
gh api "repos/{owner}/{repo}/branches/{branch}/protection" \
  --jq '.required_status_checks.contexts' 2>/dev/null

# 2. ruleset（classic が取れない場合）
gh api "repos/{owner}/{repo}/rulesets" --jq '.[].name' 2>/dev/null
gh api "repos/{owner}/{repo}/rulesets/{id}" \
  --jq '.rules[] | select(.type=="required_status_checks")' 2>/dev/null

# 3. どちらも取得できない場合
# → 「未確認（権限不足）」と記録し、ユーザーに Settings > Branches の確認を促す。
#    「未設定」と断定しない。
```

**判定**: ワークフローに存在するジョブ名が required contexts に含まれていなければ、そのジョブは**ゲートではない** → 🔴。

## 実行時間の健全性

| 観点 | 目安 | 対処案 |
|---|---|---|
| PR CI の wall-clock | 10分以内 | matrix 分割、`/e2e-turbo` の二段並列 |
| 依存インストール | キャッシュ必須 | `actions/setup-*` の cache、`oven-sh/setup-bun` |
| `timeout-minutes` | 全ジョブに設定 | 既定 360 分はハング時に致命的 |
| concurrency | 設定推奨 | 古い実行を `cancel-in-progress` で打ち切る |

## Issue に添える YAML 断片（例）

カバレッジゲート（bun + vitest）:
```yaml
  coverage:
    runs-on: ubuntu-latest
    timeout-minutes: 10
    steps:
      - uses: actions/checkout@v4
        with: { fetch-depth: 0 }
      - uses: oven-sh/setup-bun@v2
      - run: bun install --frozen-lockfile
      - run: bun run vitest run --coverage
      # vitest.config.ts の coverage.thresholds で未達時に fail させる
```

`vitest.config.ts`:
```ts
coverage: {
  provider: 'v8',
  reporter: ['text', 'json-summary', 'lcov'],
  thresholds: { lines: 80, branches: 70, functions: 80, statements: 80 },
}
```

差分カバレッジ（diff-cover）:
```yaml
      - run: pipx run diff-cover coverage/lcov.info --compare-branch=origin/main --fail-under=90
```

**これらは Issue の本文に載せるだけで、スキル内でファイルに適用しない。**
