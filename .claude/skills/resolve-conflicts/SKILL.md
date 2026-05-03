---
name: resolve-conflicts
description: PR番号を指定してコンフリクトをworktreeで安全に解消する
user-invocable: true
---

# resolve-conflicts

PR のコンフリクトを worktree で隔離して安全に解消する。

## 前提条件

- Claude Code 環境
- `git`, `gh` CLI

## 引数

- **PR 番号** (例: `/resolve-conflicts #123` or `/resolve-conflicts 123`)
- **PR URL** (例: `/resolve-conflicts https://github.com/owner/repo/pull/123`)
- **引数なし**: ユーザーに PR 番号をヒアリング

## フェーズ1: PR情報の取得と worktree 作成

1. 引数から PR を特定する
   - `gh pr view <番号またはURL> --json number,title,baseRefName,headRefName,headRepository,headRepositoryOwner,mergeable,url` で情報を取得
   - 引数なし: ユーザーに PR 番号を尋ねる
2. PR 情報を表示し確認する
   - PR タイトル、ベースブランチ、ヘッドブランチ、コンフリクト状態
   - mergeable が `CONFLICTING` でない場合: コンフリクトなしと報告して終了
3. ベースブランチとヘッドブランチを記録する
4. 解消戦略をユーザーに確認する（AskUserQuestion）
   - **rebase**（推奨）: ヘッドブランチをベースブランチ上にリベース。履歴がきれい。push 時に `--force-with-lease` が必要
   - **merge**: ベースブランチをヘッドブランチにマージ。マージコミットが追加される。通常の push で済む
5. **git worktree を作成する**（手順は `references/worktree-setup.md` を参照）
   - ブランチ名: `resolve/<PR番号>` (例: `resolve/#123`)
   - worktree 作成後、ヘッドブランチの内容をチェックアウトする:
     ```bash
     cd <worktree-path>
     git fetch origin
     git reset --hard origin/<ヘッドブランチ>
     ```

## フェーズ2: コンフリクト解消

**重要: すべての操作は worktree ディレクトリ内で行う。**

### rebase 戦略の場合

1. worktree 内でリベースを開始する
   ```bash
   git rebase origin/<ベースブランチ>
   ```
2. コンフリクトが発生したファイルを確認する
   ```bash
   git diff --name-only --diff-filter=U
   ```
3. **各コンフリクトファイルに対して:**
   a. ファイル全体を Read で読む（コンフリクトマーカーを含む）
   b. ベースブランチ側の変更意図を理解する（`git log origin/<ベースブランチ> -- <ファイル>` で最近の変更を確認）
   c. ヘッドブランチ側の変更意図を理解する（`git log HEAD -- <ファイル>` で最近の変更を確認）
   d. 両方の変更意図を保持する形で解消する。判断に迷う場合はユーザーに確認する
   e. Edit でコンフリクトマーカーを解消する
   f. `git add <ファイル>` でステージング
4. すべてのコンフリクトを解消したら:
   ```bash
   git rebase --continue
   ```
5. 新たなコンフリクトが発生したら手順 2-4 を繰り返す
6. リベースが完了するまで繰り返す

### merge 戦略の場合

1. worktree 内でマージを開始する
   ```bash
   git merge origin/<ベースブランチ>
   ```
2. コンフリクトが発生したファイルを確認する（rebase と同じ手順 2-3）
3. 各コンフリクトを解消する（rebase と同じ手順 3a-3f）
4. すべてのコンフリクトを解消したら:
   ```bash
   git add .
   git commit  # マージコミットを作成
   ```

### 解消のガイドライン

- **両方の変更を保持**: 可能な限り両方の変更を統合する
- **意図を優先**: 行単位ではなく変更の意図を理解して解消する
- **不明点はユーザーに確認**: ビジネスロジックの判断が必要な場合は必ず聞く
- **テスト/型チェック**: 解消後にテストや型チェックが通ることを確認する

## フェーズ3: 検証と Push

1. **ビルド・テストの実行**（worktree ディレクトリ内）
   - プロジェクトにテストコマンドがあれば実行する
   - 失敗した場合は修正してコミット
2. **Push**（worktree ディレクトリ内）
   - rebase 戦略: `git push origin HEAD:<ヘッドブランチ> --force-with-lease`
   - merge 戦略: `git push origin HEAD:<ヘッドブランチ>`
3. PR のコンフリクト状態を確認する
   - `gh pr view <番号> --json mergeable` で MERGEABLE になったことを確認
4. 解消サマリーと **worktree パス** をユーザーに報告する

報告例:
```
## 完了
- PR: <URL>
- 戦略: rebase / merge
- 解消ファイル数: N 件
  - path/to/file1.ts: 両方の変更を統合
  - path/to/file2.ts: ベース側の新しいインポートを追加
- Worktree: <パス>（確認後 `git worktree remove <パス>` で削除可能）
```

## ルール

- コンフリクト解消以外の変更を加えない
- ビジネスロジックの判断が必要な場合はユーザーに確認する
- `--force-with-lease` を使い、他の人のコミットを上書きしない
- **すべての git / ファイル操作は worktree ディレクトリ内で行う。メインの作業ツリーを変更しない。**
- push 前にユーザーの確認を得る（特に rebase + force push の場合）
