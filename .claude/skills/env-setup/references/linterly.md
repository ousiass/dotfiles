# Linterly リファレンス

コード行数をチェックする軽量リンター。ファイル・ディレクトリ単位で行数上限を設定し、肥大化を防ぐ。

## インストール

```bash
# Go
go install github.com/ousiassllc/linterly/cmd/linterly@latest

# bun
bun add -D @linterly/cli
```

## 基本コマンド

```bash
linterly init          # .linterly.yml 生成
linterly check         # チェック実行
linterly check src/    # ディレクトリ指定
linterly check --format json  # JSON出力
```

## 設定ファイル (.linterly.yml)

```yaml
rules:
  # max_lines_per_file / max_lines_per_directory はデフォルト値（300/2000）を推奨。
  # 特別な理由がない限り変更しない。
  # max_lines_per_file: 300
  # max_lines_per_directory: 2000
  warning_threshold: 10       # 早めに警告を出す

count_mode: all               # 変更しない（"all" or "code_only"）
default_excludes: true        # ビルド成果物等のデフォルト除外を有効化
language: ja

# ignore でパス別に除外する場合も慎重に。
# 生成コードなど明確な理由がある場合のみ追加する。
# ignore:
#   - "src/generated/**"
```

## 除外設定 (.linterlyignore)

gitignore 形式。`default_excludes: true` により `.git/`, `dist/`, `node_modules/`,
`vendor/`, `*.min.js`, `*.lock` 等は自動除外される。
md・yml・json・toml 等はデフォルト除外に含まれないが、linterly のチェック対象外拡張子であれば無視される。
手書きソースコードの除外は基本追加しない。
```
# 自動生成コード（必要に応じて追加）
# *.generated.go
# *.pb.go
```

## 違反レベル

- `warn`: 閾値超え（終了コード0）
- `error`: 上限超え（終了コード1）

## CI連携（GitHub Actions）

```yaml
- name: Linterly check
  run: bunx linterly check
```

## Git Hooks連携

Lefthook:
```yaml
pre-commit:
  commands:
    linterly:
      run: bunx linterly check {staged_files}
```
