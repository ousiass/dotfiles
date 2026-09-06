---
name: test-audit
description: テスト・カバレッジ・CI の抜け漏れを3軸で検査し、レポートまたは Issue 化する
user-invocable: true
---

# test-audit

「テストが十分か」を **テスト・カバレッジ・CI の3軸** で監査し、漏れを具体的な単位で検出する。成果物はレポートと Issue のみで、**コード・設定ファイルは変更しない**（修正は `/impl` や `/e2e-turbo` に渡す）。

## 前提条件

- Claude Code 環境
- `gh` CLI（Issue 作成・branch protection 確認時）
- カバレッジ実測を行う場合、依存インストール済みでテストが通ること

## 引数

- **引数なし**: リポジトリ全体を監査
- **パス指定** (例: `/test-audit src/api`): 対象ディレクトリに絞る
- `--no-run`: テスト／カバレッジを実行せず、静的解析と設定ファイルのみで判定する（CI が壊れている・時間がない場合）
- `--ci-only`: CI 軸（軸C）のみ実行

## 監査の3軸

| 軸 | 問い | 参照 |
|---|---|---|
| A. テスト | テストが**存在するか**、そのテストが**意味を持つか** | `references/check-criteria.md` |
| B. カバレッジ | 計測・閾値・差分カバレッジの**仕組みがあるか**、実測値が基準を満たすか | `references/check-criteria.md` |
| C. CI | 上記が **PR で自動的に強制されるか**（ゲートとして機能しているか） | `references/ci-baseline.md` |

**軸Cが最重要**。テストがあってもCIで走らない／落ちても止まらないなら、網羅は担保されない。ローカルで通るだけの状態は 🔴 として扱う。

## フェーズ0: 検出と初回ヒアリング

### 0-1: 現状検出

以下を調べ、プロジェクトの形を確定する（推測しない）:

- **言語・パッケージマネージャ**: `package.json` / `go.mod` / `pyproject.toml` / `Cargo.toml` / `Gemfile` 等
- **テストランナーとカバレッジツール**: 依存とスクリプト、`vitest.config.*` / `jest.config.*` / `playwright.config.*` / `pytest.ini` / `.nycrc` 等
- **テストの配置規約**: `__tests__/`, `*.test.ts`, `*_test.go`, `tests/` のどれか（既存規約に従う）
- **CI**: `.github/workflows/*.yml`（無ければ `.gitlab-ci.yml`, `circleci`, `Jenkinsfile` も探す）
- **hooks**: `lefthook.yml` / `.husky/` / `pre-commit`
- **カバレッジ成果物の送信先**: Codecov / Coveralls / SonarQube 等の設定
- **既存の閾値設定**: `coverageThreshold`, `--cov-fail-under`, `thresholds` 等

TS/JS プロジェクトではコマンド例を **bun** で提示する。

### 0-2: まとめてヒアリング

`AskUserQuestion` で一度に聞く（最大4問）。検出で一意に決まった項目は聞かない。

1. **カバレッジを実測するか**
   - 実測する（推奨・正確だが時間がかかる）／ 静的解析のみ（`--no-run` 相当）
2. **目標とする閾値**（既存設定があればそれを既定値として提示）
   - 全体 line/branch と、差分カバレッジの目標値
3. **監査対象スコープ**（引数で指定済みならスキップ）
   - リポジトリ全体 ／ 特定ディレクトリ ／ 変更が多い箇所のみ
4. **出力先**
   - GitHub Issue ／ ローカル MD (`test-audit-report.md`) ／ コンソール

以降は完了まで割り込まない。追加の不明点が出たら、その時点でまとめて1回だけ聞く。

## フェーズ1: 軸A — テストの監査

検知観点とパターンは `references/check-criteria.md` を参照。

### 1-1: テスト不在の検出

1. 対象のソースファイルを `Glob` で列挙し、プロジェクトの規約に沿った対応テストファイルを探す
2. 対応テストが無いファイルを列挙する
3. **重要度で仕分ける**（全ファイル一律に報告しない）:
   - 🔴 認証・認可・課金・決済・データ削除／更新・外部送信を含むファイル
   - 🟠 ビジネスロジック（分岐が多い、純関数でない）
   - 🟡 その他
   - 除外: 型定義のみ、定数のみ、自動生成、エントリポイントの薄い配線

### 1-2: テスト層の欠落

unit / integration / E2E のどの層が存在するかを判定し、欠落を報告する。
- API を持つのに HTTP レイヤの結合テストが無い
- 画面があるのに E2E が無い（→ `/e2e-turbo` を推奨として Issue に書く）
- DB を持つのにマイグレーション／クエリのテストが無い

### 1-3: テスト品質のアンチパターン

`Grep` で検出する（パターンは `references/check-criteria.md`）:
- **アサーションが無いテスト**（実行するだけで何も検証していない）
- `skip` / `only` の残存（`only` は他テストを丸ごと無効化するため 🔴）
- 常に真になるアサーション（`expect(true).toBe(true)`、`assert.NotNil(err)` の誤用等）
- スナップショットのみのテスト（振る舞いを検証していない）
- 異常系・境界値の欠落（正常系のみの `describe` ブロック）
- 実ネットワーク・実時刻・実乱数への依存（flaky の温床）

## フェーズ2: 軸B — カバレッジの監査

### 2-1: 仕組みの監査（実測より優先）

| チェック | 欠落時の重大度 |
|---|---|
| カバレッジ計測が設定されているか | 🔴 |
| 閾値（fail-under）が設定されているか | 🔴 |
| 閾値が実測値より不当に低くないか（形骸化） | 🟠 |
| 差分カバレッジ（変更行）の仕組みがあるか | 🟠 |
| 計測対象からの除外設定が過剰でないか（`exclude` で本体を除外していないか） | 🟠 |
| E2E／結合テストのカバレッジが合算されているか | 🟡 |

### 2-2: 実測（`--no-run` でない場合）

1. `references/check-criteria.md` の言語別コマンドでカバレッジを実行する
2. 失敗したら**そこで実測を止め、失敗自体を 🔴 の検出項目として記録**する（推測値で埋めない）
3. `coverage-summary.json` / `lcov.info` / `coverage.xml` 等を解析し、ファイル単位の値を取得
4. 閾値未達のファイルを列挙し、1-1 の重要度仕分けと突き合わせて優先度を付ける
5. 差分カバレッジ: `git diff --name-only <base>...HEAD` の変更行に対する被覆率を算出する

**カバレッジ数値だけで「十分」と判定しない。** 高カバレッジでもアサーションが無ければ意味がないため、必ず 1-3 の結果と併記する。

## フェーズ3: 軸C — CI の監査

ベースラインと判定手順は `references/ci-baseline.md` を参照。

1. ワークフローを全て読み、**ジョブ × トリガ** の表を作る
2. ベースライン（lint / format / typecheck / build / unit / integration / E2E / カバレッジゲート / 依存監査）との差分を取る
3. **テストが実質無効化されていないか**を検査（`references/ci-baseline.md` のアンチパターン）:
   - `continue-on-error: true`、`|| true`、`if: false`
   - `paths` / `paths-ignore` フィルタで実際には走らない
   - E2E が `schedule` / `workflow_dispatch` のみで PR で走らない
   - カバレッジを出力するだけで閾値判定していない
4. **required status checks** を確認する:
   ```bash
   gh api "repos/{owner}/{repo}/branches/{branch}/protection" --jq '.required_status_checks.contexts' 2>/dev/null
   ```
   権限不足やルールセット利用で取得できない場合は `gh api "repos/{owner}/{repo}/rulesets"` を試し、それも不可なら「未確認」として記録する（「未設定」と断定しない）
5. ジョブが存在しても required check に入っていなければ 🔴（落ちてもマージできる＝ゲートではない）
6. 実行環境の健全性: タイムアウト未設定、キャッシュ未使用、matrix 未使用による長時間化は 🟡 として記録

## フェーズ4: レポート生成と出力

1. 検出結果を軸別・重大度別に集計する（重大度基準は `references/check-criteria.md`）
2. `templates/report.md` の形式でレポートを生成する
3. **「網羅への残タスク」を優先順にリスト化**する。各項目に「これを埋めると何が守られるか」を1行で添える
4. フェーズ0 で決めた出力先に出す（未確定なら `AskUserQuestion` で確認）

## フェーズ5: Issue 作成

出力先が GitHub Issue の場合:

1. 全件の一覧（タイトル + 軸 + 重大度）をまとめて表示する
2. `AskUserQuestion` で作成方式を確認:
   - **軸ごとに1 Issue**（推奨）: テスト／カバレッジ／CI の3 Issue にチェックリストでまとめる
   - **まとめて1 Issue**: 全件を1つのチェックリストに
   - **個別 Issue**: 1件1 Issue（`/issue-sweep` で消化する場合に有効）
3. 重複チェック: `gh issue list --state open --search "<要約>" --label test-audit`
4. 本文は `templates/issue.md` に従う。**CI 系の Issue には適用可能な YAML 断片を含める**（実際の適用は行わない）
5. `gh issue create` で作成。ラベル: `test-audit` + `severity:*` + 軸ラベル（`test`, `coverage`, `ci`）
6. 作成した Issue の URL を報告し、消化には `/issue-sweep` または `/impl` を使うことを伝える

## ルール

- **コード・設定ファイルを変更しない**。成果物はレポートと Issue のみ
- 推測で報告しない。**該当ファイル:行 または設定の該当箇所を必ず示す**
- テスト不在は全件羅列せず、**重要度で仕分けてから**報告する（ノイズは Issue を死なせる）
- カバレッジ数値と「テストが意味を持つか」は別問題として、必ず両方報告する
- 「CI に無いから 🔴」ではなく、「落ちてもマージできるから 🔴」という**ゲートとして機能するか**の観点で判定する
- `TaskCreate` / `TaskUpdate` で3軸の進捗を管理する
- Issue 作成前に必ず承認を得る
