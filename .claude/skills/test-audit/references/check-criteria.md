# 検知観点・パターン・重大度基準

## 軸A: テストの検知観点

| 観点 | 検知内容 | 手段 |
|---|---|---|
| テスト不在 | ソースファイルに対応するテストが無い | Glob で対応付け |
| 層の欠落 | unit / integration / E2E のいずれかが存在しない | Glob / config |
| 空テスト | アサーションを含まない `it` / `test` / `func Test` | Grep + Read |
| 無効化 | `skip` / `only` / `xit` / `t.Skip` / `@Disabled` | Grep |
| 無意味なアサーション | 常に真、実装をそのまま写した期待値 | Read |
| 異常系欠落 | 正常系のみ。エラー・境界値・権限拒否のケースが無い | Read |
| flaky 要因 | 実ネットワーク、`Date.now()`、`Math.random()`、`sleep` 依存 | Grep |
| モック過剰 | 対象そのものをモックしていて実質何も検証していない | Read |

### テスト不在の対応付け規約

| 言語 | ソース | テスト |
|---|---|---|
| TS/JS | `src/foo/bar.ts` | `src/foo/bar.test.ts`, `src/foo/__tests__/bar.test.ts`, `tests/foo/bar.test.ts` |
| Go | `foo/bar.go` | `foo/bar_test.go` |
| Python | `src/foo/bar.py` | `tests/foo/test_bar.py`, `tests/test_bar.py` |
| Ruby | `app/foo/bar.rb` | `spec/foo/bar_spec.rb`, `test/foo/bar_test.rb` |
| Rust | `src/foo.rs` | 同ファイル内 `#[cfg(test)] mod tests` または `tests/foo.rs` |

**除外してよいファイル**: 型定義のみ（`*.d.ts`, `types.ts`）、定数のみ、自動生成（`*.gen.*`, `*_pb.go`, `migrations/`）、設定ファイル、薄いエントリポイント配線。

### Grep パターン

**無効化されたテスト**

| 言語 | パターン |
|---|---|
| JS/TS | `it.skip`, `describe.skip`, `test.skip`, `xit`, `xdescribe`, `it.only`, `describe.only`, `test.only`, `test.todo`, `test.fixme` |
| Go | `t.Skip`, `t.SkipNow` |
| Python | `@pytest.mark.skip`, `@pytest.mark.xfail`, `@unittest.skip`, `pytest.skip(` |
| Ruby | `xit `, `skip `, `pending ` |
| Java | `@Disabled`, `@Ignore` |
| Rust | `#[ignore]` |

`only` 系は**同ファイルの他テストを全て無効化する**ため、CI に混入していれば常に 🔴。

**アサーション不在の検出手順**（Grep だけでは判定できないため2段階）
1. テスト関数の一覧を Grep で取得
2. 各テスト本体に `expect(` / `assert` / `require.` / `should` / `t.Error` / `t.Fatal` が無いものを Read で確認

**flaky 要因**
```
Date.now\(|new Date\(\)|Math.random\(|setTimeout|sleep\(|time.Sleep|waitForTimeout
fetch\(['"]https?://|axios.(get|post)\(['"]https?://
```
（テストファイル内でのみ検索。`waitForTimeout` は Playwright の固定待ちで flaky 直結）

## 軸B: カバレッジの検知観点

| 観点 | 欠落・問題 | 確認先 |
|---|---|---|
| 計測の有無 | カバレッジオプション・ツールが未設定 | package.json / config |
| 閾値 | fail-under が無い、または `0` | config |
| 閾値の形骸化 | 実測 85% に対し閾値 40% 等 | 実測との比較 |
| 除外の過剰 | `exclude` / `omit` に本体コードが入っている | config |
| 差分カバレッジ | 変更行に対する被覆判定が無い | CI / config |
| 合算漏れ | E2E・結合のカバレッジが合算されていない | CI |
| ブランチ網羅 | line のみ計測し branch を見ていない | config |

### 言語別コマンド

| 環境 | 実行 | 出力 |
|---|---|---|
| Vitest | `bun run vitest run --coverage --coverage.reporter=json-summary --coverage.reporter=lcov` | `coverage/coverage-summary.json` |
| Jest | `bun run jest --coverage --coverageReporters=json-summary --coverageReporters=lcov` | 同上 |
| Go | `go test ./... -coverprofile=coverage.out -covermode=atomic` → `go tool cover -func=coverage.out` | `coverage.out` |
| pytest | `pytest --cov=. --cov-report=xml --cov-report=term` | `coverage.xml` |
| Rust | `cargo llvm-cov --lcov --output-path lcov.info` | `lcov.info` |
| Ruby | SimpleCov（`COVERAGE=1 bundle exec rspec`） | `coverage/.last_run.json` |

### 差分カバレッジの実現手段（Issue で提案する候補）

| 環境 | 手段 |
|---|---|
| 汎用（lcov / xml） | `diff-cover`（Python 製、lcov・cobertura 対応） |
| Codecov | `codecov.yml` の `status.patch.target` |
| JS/TS | `vitest --changed` + `--coverage.thresholds` |
| Go | `gocovsh` / `go tool cover` + 変更行フィルタ |

閾値の推奨値: **全体 line 80% / branch 70%、差分（patch）90%**。既存プロジェクトの実測が下回る場合は、現状値を下限として固定し段階的に引き上げる案を併記する。

## 重大度基準

| 重大度 | 基準 | Issue |
|---|---|---|
| 🔴 重大 | CI にテストジョブが無い／落ちてもマージできる／`only` が混入／カバレッジ閾値が無い／認証・課金・データ破壊系にテストが無い／テスト実行自体が失敗する | 必須 |
| 🟠 重要 | E2E や結合が PR で走らない／アサーション不在のテスト／skip 残存／閾値が形骸化／ビジネスロジックにテストが無い／差分カバレッジ無し | 必須 |
| 🟡 注意 | 異常系・境界値の欠落／flaky 要因／カバレッジ閾値未達（重要度の低いファイル）／CI にタイムアウト・キャッシュが無い | 推奨 |
| 🟢 軽微 | テスト命名の不統一／重複テスト／レポータ設定の不足 | 任意 |
