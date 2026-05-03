# Worktree セットアップ手順

## 作成

```bash
# ベースブランチの最新を取得
git fetch origin

# worktree を作成（新しいブランチ付き）
git worktree add <worktree-path> -b <branch-name>
```

### worktree パスの規則

```
.claude/worktrees/<branch-name>/
```

- リポジトリルートからの相対パス
- ブランチ名の `/` は `-` に置換する（例: `fix/#42` → `fix-#42`）

### 例

```bash
# Issue #42 の場合
git worktree add .claude/worktrees/fix-#42 -b fix/#42

# テキスト指定の場合
git worktree add .claude/worktrees/fix-login-500-error -b fix/login-500-error
```

## 確認

```bash
# worktree 一覧
git worktree list
```

## 削除（ユーザーが手動で行う）

```bash
git worktree remove <worktree-path>
```
