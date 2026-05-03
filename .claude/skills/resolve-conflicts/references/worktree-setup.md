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
- ブランチ名の `/` は `-` に置換する（例: `resolve/#123` → `resolve-#123`）

### 例

```bash
# PR #123 の場合
git worktree add .claude/worktrees/resolve-#123 -b resolve/#123

# worktree 内でヘッドブランチの内容をチェックアウト
cd .claude/worktrees/resolve-#123
git fetch origin
git reset --hard origin/<ヘッドブランチ>
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
