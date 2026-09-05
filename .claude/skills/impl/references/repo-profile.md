# repo プロファイル

同じリポジトリで impl を回すたびにテストコマンド・lint 設定・仕様書パスを探索し直すのは無駄なので、リポジトリ単位でキャッシュする。

## 保存先

```bash
PROFILE=$(~/.claude/skills/impl/scripts/verify-scope.sh --profile-path)
```

`~/.claude/cache/repo-profile/<git-common-dir の sha256 先頭16桁>.json` を返す。パスの算出はこのスクリプトが単一の正とし、他の場所で再実装しない。

- `.claude/cache/` は dotfiles の `.gitignore` 対象なので、ユーザーのリポジトリを一切汚さない
- キーが **git common dir** なので、同一リポジトリの worktree はすべて同じプロファイルを共有する（worktree を作るたびに探索し直す必要がない）

## スキーマ

```json
{
  "generated_at": "2026-09-05T10:00:00Z",
  "pm": "bun",
  "test_cmd": "bun test",
  "lint_cmd": "bun run lint",
  "format_cmd": "bun run format",
  "spec_paths": ["docs/spec", "README.md"],
  "test_layout": "実装と同ディレクトリに <name>.test.ts",
  "notes": "CI は .github/workflows/ci.yml。typecheck は lint_cmd に含む"
}
```

- 値が確定しなかったキーは**空文字 / 空配列にする**（推測で埋めない）。`test_cmd` が空なら verify-scope.sh はテスト検査を SKIP と報告する
- `test_cmd` / `lint_cmd` はリポジトリルートで動く 1 行のシェルコマンドにする

## 生成

フェーズ1 でプロファイルが無い場合のみ作る。判断材料は以下の順で見る。

1. `CLAUDE.md` の記載（あれば最優先）
2. パッケージマネージャの manifest（`package.json` の `scripts`、`Makefile`、`pyproject.toml`、`go.mod`、`Cargo.toml` 等）
3. CI 設定（`.github/workflows/*.yml` が実際に叩いているコマンド）

```bash
PROFILE=$(~/.claude/skills/impl/scripts/verify-scope.sh --profile-path)
mkdir -p "$(dirname "$PROFILE")"
jq -n --arg pm bun --arg test 'bun test' --arg lint 'bun run lint' \
      --arg format 'bun run format' --arg layout '実装と同ディレクトリに <name>.test.ts' \
      --argjson specs '["docs/spec"]' --arg notes '' \
      '{generated_at: (now | todate), pm: $pm, test_cmd: $test, lint_cmd: $lint,
        format_cmd: $format, spec_paths: $specs, test_layout: $layout, notes: $notes}' > "$PROFILE"
```

## 破棄する条件

キャッシュが古いまま使われる事故を防ぐため、**以下のいずれかに当てはまったら読まずに作り直す**。

- `generated_at` から 30 日以上経過している
- プロファイルの `test_cmd` / `lint_cmd` が「コマンドが見つからない」で落ちた（verify-scope.sh の FAIL ログで判別できる）
- 今回の変更で manifest（`package.json` 等）や CI 設定自体を触った
