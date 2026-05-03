---
name: release
description: changelog 生成、バージョンタグ、GitHub リリースノート、レジストリ publish を行う。
user-invocable: true
---

# release

## 前提条件

- Claude Code 環境
- `git`, `gh` CLI

## 引数

- **バージョン** (例: `/release v1.2.0`): 指定バージョンでリリース
- **バージョンタイプ** (例: `/release patch`): 現在のバージョンから自動決定
- **引数なし**: 変更内容からバージョンタイプを提案しユーザーに確認

## フェーズ0: リリースオプションの確認

### 0-1. マニフェスト検出

プロジェクトルートで以下を検出し、publish 候補を特定する：

| マニフェスト | レジストリ | publish コマンド |
|---|---|---|
| `package.json` | npm | `npm publish` |
| `pyproject.toml` / `setup.py` | PyPI | `python -m build && twine upload dist/*` |
| `Cargo.toml` | crates.io | `cargo publish` |
| `*.gemspec` | RubyGems | `gem build && gem push` |
| `*.csproj` / `*.nuspec` | NuGet | `dotnet pack && dotnet nuget push` |
| `mix.exs` | Hex | `mix hex.publish` |

monorepo（`workspaces`, `pnpm-workspace.yaml`, `lerna.json`）を検出した場合は、対象パッケージをユーザーに確認する。

**以下のいずれかに該当する場合、publish は不要と判断しユーザーに聞かない：**

- `package.json` に `"private": true` がある
- CI ワークフロー（`.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml` など）に publish ステップが既にある
- マニフェストに `version` フィールドがない
- アプリケーション（ライブラリではない）と明らかに判断できる場合

### 0-1b. CI リリース検出

CI ワークフロー（`.github/workflows/`, `Jenkinsfile`, `.gitlab-ci.yml` など）を走査し、**CI が GitHub Release を作成するか**を判定する。

**以下のいずれかを検出した場合、CI がリリースを作成すると判断する（`ci_creates_release = true`）：**

- `goreleaser` / `goreleaser-action`（GoReleaser）
- `softprops/action-gh-release`
- `ncipollo/release-action`
- `gh release create` をワークフロー内で実行している
- その他、GitHub Release を作成する Action やスクリプト

`ci_creates_release = true` の場合、フェーズ6 で `gh release create` をスキップする（タグ push で CI に委ねる）。

### 0-2. ユーザー確認

`AskUserQuestion` で以下を確認：

1. **ブランチマージ**: リリース前にブランチをマージするか（マージ元・マージ先も確認）
2. **バイナリビルド**: ビルド成果物を添付するか（ビルドコマンドと成果物パスも確認）
3. **レジストリ publish**: マニフェストが検出され、かつ上記の「不要」条件に該当しない場合のみ表示。「<レジストリ名> に publish しますか？」と確認（OTP 要否、scoped パッケージの `--access public` なども必要に応じて確認）

## フェーズ1: マージ（該当時のみ）

1. マージ元ブランチが最新か確認する（`git fetch && git log`）
2. マージ先にチェックアウト → `git merge --no-ff <マージ元>`
3. コンフリクトがあればユーザーに報告して中断

## フェーズ2: 変更内容の収集

1. 最新のリリースタグを取得する（`gh release list` / `git tag`）
2. 前回リリースから現在までのコミット・マージ PR を収集
3. 変更カテゴリ（`templates/changelog.md` を参照）で分類する

## フェーズ3: バージョン決定

1. 引数でバージョン指定あり → そのまま使用
2. 指定なし → 変更内容から提案：
   - 破壊的変更あり → **major**
   - 新機能あり → **minor**
   - バグ修正・改善のみ → **patch**
3. ユーザーに確認し合意を得る

## フェーズ4: Changelog 生成

1. `CHANGELOG.md` が存在するか確認（なければ新規作成、あれば先頭に追記）
2. `templates/changelog.md` の形式で追記する
3. 各エントリは `英語 / 日本語` の日英併記。コミットメッセージから生成

## フェーズ5: バージョン更新（レジストリ publish 時のみ）

マニフェストファイルのバージョンを更新する：

| レジストリ | 更新対象 | 方法 |
|---|---|---|
| npm | `package.json` の `version` | `npm version <ver> --no-git-tag-version` |
| PyPI | `pyproject.toml` の `version` / `setup.py` | 直接編集 |
| crates.io | `Cargo.toml` の `version` | 直接編集 |
| RubyGems | gemspec の `version` | 直接編集 |
| NuGet | csproj の `Version` | 直接編集 |
| Hex | `mix.exs` の `version` | 直接編集 |

lock ファイル（`package-lock.json`, `Cargo.lock` など）も更新が必要な場合は適切に対応する。

## フェーズ5b: ビルド（該当時のみ）

1. ビルドコマンドを実行
2. 成果物の存在を確認
3. 失敗時はユーザーに報告して中断

## フェーズ6: リリース作成

1. Changelog をコミット（`docs: v<バージョン> の changelog を追加`）
2. タグを作成（`git tag v<バージョン>`）
3. プッシュ（`git push && git push --tags`）
4. **`ci_creates_release = false` の場合:** `gh release create v<バージョン>` でリリース作成（成果物があれば添付）
   **`ci_creates_release = true` の場合:** タグ push で CI がリリースを作成するため、`gh release create` はスキップ。ユーザーに「CI がリリースを作成します」と報告する
5. リリース URL をユーザーに報告（CI 委譲時は CI ワークフローの URL を案内）

## フェーズ7: レジストリ publish（該当時のみ）

フェーズ0 で publish を承認された場合のみ実行。

1. dry-run で事前確認（`npm publish --dry-run`, `twine check dist/*` など）
2. dry-run の結果をユーザーに表示し、最終確認を取る
3. publish を実行
4. publish 後、レジストリ上のパッケージ URL をユーザーに報告

**レジストリ別コマンド：**

| レジストリ | dry-run | publish |
|---|---|---|
| npm | `npm publish --dry-run` | `npm publish`（scoped は `--access public`） |
| PyPI | `twine check dist/*` | `twine upload dist/*` |
| crates.io | `cargo publish --dry-run` | `cargo publish` |
| RubyGems | `gem build *.gemspec` | `gem push *.gem` |
| NuGet | `dotnet pack` | `dotnet nuget push` |
| Hex | `mix hex.publish --dry-run` | `mix hex.publish` |

OTP が必要な場合はユーザーに入力を求める。

## ルール

- バージョンは必ずユーザーの合意を得てから確定する
- Changelog は事実ベース。コミットメッセージや PR タイトルを元にする
- 破壊的変更は必ず ⚠️ セクションに明記する
- リモートへのプッシュ・リリース作成の前にユーザーに確認する
- TaskCreate/TaskUpdate で進捗を管理する
