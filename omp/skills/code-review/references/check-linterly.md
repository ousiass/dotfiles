# Linterly チェック項目

行数チェックツール [Linterly](https://github.com/ousiassllc/Linterly) の導入・設定を検証する。

## チェック項目

| チェック項目 | 基準 |
|------------|------|
| **インストール** | `@linterly/cli`（npm）または `go install` でインストールされているか。`package.json` の devDependencies または `go.mod` で確認 |
| **設定ファイル** | `.linterly.yml` がプロジェクトルートに存在するか |
| **デフォルト値の維持** | 下記のデフォルト値が変更されていないか。変更されている場合は 🟠 重要 で指摘し、変更理由の正当性を確認する |
| **ignore の濫用防止** | `.linterlyignore` や `.linterly.yml` の `ignore` に、行数制限を回避するための不要な除外パターンが追加されていないか |
| **lefthook 統合** | `lefthook.yml` の pre-commit に `linterly check` が含まれているか。未設定なら導入を提案 |

## デフォルト設定値

```yaml
rules:
  max_lines_per_file: 300
  max_lines_per_directory: 2000
  warning_threshold: 10
count_mode: all
default_excludes: true
```

これらの値は変更しないことが原則。特に `max_lines_per_file` と `max_lines_per_directory` の引き上げは行数制限の形骸化につながるため、強く警告する。

## 許容される ignore パターン

以下のような自動生成ファイル・バイナリの除外は許容：

- `*.pb.go`, `*_generated.*`, `*.gen.*`（コード生成）
- `*.min.js`, `*.min.css`（minified）
- `vendor/**`（依存パッケージ）
- `dist/**`, `build/**`（ビルド成果物）

## 指摘すべき ignore パターン

以下のような手書きソースコードの除外は 🟠 重要 で指摘：

- 特定のソースファイル名（例: `src/bigFile.ts`）
- ソースディレクトリの広範な除外（例: `src/legacy/**`）
- ワイルドカードによるソースコード除外（例: `**/*.service.ts`）

ファイルが行数制限を超える場合、ignore に追加するのではなくファイル分割で対処すべき。

## lefthook 統合の推奨設定

```yaml
# lefthook.yml
pre-commit:
  commands:
    linterly:
      glob: "*.{go,ts,tsx,js,jsx,py,rb,java,rs}"
      run: linterly check {staged_files}
```
