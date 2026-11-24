---
name: merge-chain
description: 複数の PR を書いた順に、main の取り込み・CI 待ち・マージコミットでのマージまで1本ずつ進める。
---

# merge-chain

指定した PR を、書いた順に 1 本ずつ「main を取り込む → PR の CI が緑 → マージコミットでマージ → main の CI が緑」で片付ける。前の PR が main に入ってから次の PR の衝突を見るので、後ろの PR ほど衝突が出やすい並びでも順に解消できる。

## 引数

- `/merge-chain <owner/repo> #A #B ...` — `#A #B ...` の順にマージする
- 各 PR の期待 head（SHA）は依頼文で渡される。`#A=<sha>` の形で書いてもよい。無人で回るので `ask` はしない。期待 head が無い PR が 1 本でもあれば、手順 0 の前に止め、手順 9 の報告に「期待 head 未指定: #<番号>」と書く
- 報告ファイルのパスは依頼文で指定される。なければ `/tmp/merge-chain-<owner>-<repo>-<日時>.md`

## 前提条件

- omp 環境
- `git`, `gh` CLI（認証済み）、`rg`
- `<owner/repo>` のローカル clone（`git worktree list` を使う元）。見つからなければ止めて報告する

## 禁止

amend・rebase・force push・squash・`reset --hard`・`--no-verify`・main への直接 push・リモートブランチの削除・Issue / PR の close とコメント・手動のリリースやタグ操作。フックが落ちたら飛ばさず止めて報告する。

## 全体の流れ

- 手順 0 は最初に 1 回
- 手順 1〜8 は PR ごとに順に繰り返す
- 止める条件に当たったらその場で止め、手順 9 の報告を書く

## 手順 0: main の CI を確かめる

1. デフォルトブランチ（以下 `main`）の最新コミットの run を取る

   ```bash
   gh run list -R <repo> --branch main --limit 20 --json databaseId,name,status,conclusion,headSha,event
   ```

   最新コミット（`headSha` が最も新しいもの）の run だけを見る
2. `status` が `completed` でない run があれば、終わるまで 5 分おきに取り直す（`sleep 300`）
3. 全部 `success` なら進む。1 つでも `success` でなければ止めて報告する
4. 今あるタグを控える（手順 8 で増えた分を出すため）: `git ls-remote --tags origin`

## 手順 1: head を確かめる

```bash
gh pr view <N> -R <repo> --json state,isDraft,isCrossRepository,headRefName,headRefOid,mergeable,mergeStateStatus,closingIssuesReferences
```

- `state` が `OPEN` で、`headRefOid` が依頼の期待 head と一致する。違えば止める（誰かが push した可能性がある）
- `isCrossRepository` が `true`（fork）なら push できないので止める
- 控える: 旧 head（`headRefOid`）、ブランチ名（`headRefName`）、Issue 番号（`closingIssuesReferences`、なければ PR 本文の `#<番号>`、それもなければ PR 番号）
- `mergeable` が `UNKNOWN` なら 30 秒おきに 5 回まで取り直す

## 手順 2: 衝突があれば main を取り込む

`mergeable` が `CONFLICTING` のときだけ行う。`MERGEABLE` なら手順 4 へ進む（その head の PR CI が緑かは手順 4 で確かめる）。

1. PR のブランチの worktree を探す

   ```bash
   git -C <clone> worktree list --porcelain
   ```

   `branch refs/heads/<branch>` の行がある worktree を使う。なければ既存ブランチを worktree に取り出す

   ```bash
   git -C <clone> fetch origin <branch>
   git -C <clone> worktree add --no-track /mnt/nvme/ousiassllc/.wt/<repo>-<branch を - にした名前>-merge-chain <branch>
   ```

   ローカルのブランチが無ければ `-b <branch> ... origin/<branch>` で作る。以降の操作はすべてこの worktree の中で行う
2. 作業できる状態か確かめる: `git status --short` が空で、`git rev-parse HEAD` が旧 head と一致する。違えば（未コミットの変更・ローカルがずれている）止める。直すための reset はしない
3. 取り込む

   ```bash
   git fetch origin && git merge --signoff origin/main
   ```

## 手順 3: 衝突を直して push する

1. 衝突したファイルを開き、**両方の変更を残して**直す。片方を捨てて済ませない
   - 改訂履歴・変更履歴の版番号が重なったら、main 側を先に置き、この PR の分を後ろに振り直す
2. 衝突マーカーが残っていないか確かめる

   ```bash
   git diff --name-only --diff-filter=U            # 空になるまで git add
   rg -n '^(<<<<<<<|>>>>>>>) ' -- .               # 0 件
   rg -n '^=======$' -- <衝突したファイル>          # 0 件
   ```

3. リポジトリの CI 定義（`.github/workflows` など）と同じコマンドをローカルで 1 つずつ実行する。ローカルで再現できないものは報告で「未確認」にする
4. コミットする。メッセージは `<type>: <説明>` の形で、Issue は `Refs #<Issue>` だけ書く（`Closes` / `Fixes` は書かない）

   ```bash
   git commit -s -m "merge: origin/main を取り込み衝突を解消" -m "Refs #<Issue>"
   ```

5. push する（force しない）

   ```bash
   git push origin HEAD:refs/heads/<branch>
   ```

   拒否されたら止める。新しい head は `git rev-parse HEAD` で控える

## 手順 4: PR の CI が緑になるのを待つ

1. `gh pr view <N> -R <repo> --json headRefOid` が新 head（取り込みなしなら旧 head）と一致するまで待つ。一致しなければ止める
2. その head の run を取り、終わるまで待つ

   ```bash
   gh run list -R <repo> --commit <head> --json databaseId,name,status,conclusion
   gh run watch <run-id> -R <repo> --interval 30
   ```

   push 直後は run がまだ出ないことがある。30 秒おきに 5 分まで待ち、出なければ止める
3. 全部 `success` なら進む。`skipped` は `if:` 条件による設定上の意図だと確かめられたときだけ許し、報告に理由を書く。前段の失敗で飛ばされたものは緑とみなさない
4. 失敗があれば「CI の失敗の扱い」に従う

## 手順 5: マージする

```bash
gh pr view <N> -R <repo> --json headRefOid,mergeable,mergeStateStatus
gh pr merge <N> -R <repo> --merge --match-head-commit <head>
```

- `headRefOid` が控えた head と一致し、`mergeable` が `MERGEABLE` のときだけ実行する。`CONFLICTING` に戻っていたら手順 2 からやり直す。続けて 2 回戻ったら止める
- `--squash` / `--rebase` / `--admin` は使わない。head が合わずに失敗したら止める
- マージコミットの SHA を控える: `gh pr view <N> -R <repo> --json mergeCommit --jq .mergeCommit.oid`

## 手順 6: main の CI を待つ

マージコミットで動く run（main への push で起動する CI と、あれば release）が終わるまで待つ。

```bash
gh run list -R <repo> --commit <マージコミット> --json databaseId,name,status,conclusion,event
```

- run が出るまで 30 秒おきに 5 分まで待つ。出なければ、そのリポジトリに main 向けのワークフローが無いか `.github/workflows` を見て確かめ、あるのに出ないなら止める
- 終わっていない run があれば `gh run watch` か 5 分おきの取り直しで待つ
- 全部 `success` なら手順 7 へ。失敗は「CI の失敗の扱い」に従う

## 手順 7: タグを控える

`git ls-remote --tags origin` を手順 0 の控えと比べ、増えたタグがあれば PR の行に書く。release が別の run で起動する場合は、そのタグの run も終わるまで待ち、`success` を確かめてから次の PR へ進む。タグや release を自分で作らない。

## 手順 8: 次の PR へ

`#B` 以降について手順 1 から繰り返す。main が進んでいるので、`mergeable` は必ず取り直す。

## CI の失敗の扱い

- 失敗した job のログを見て分類する: `gh run view <run-id> -R <repo> --log-failed`
- **ツール導入やネットワークのエラー**（`proxy.golang.org` への接続失敗、パッケージのダウンロードや apt / npm の取得失敗、runner のセットアップ失敗など）だけ、`gh run rerun <run-id> -R <repo> --failed` を **1 回** して、run id・原因・結果を記録する
- 次のときは再実行せず、その場で止めて報告する
  - コードの失敗（テスト・lint・ビルドの失敗）
  - 再実行がまた失敗した（2 回目の失敗）
  - head の不一致
- 失敗の原因が分かるなら、報告に job 名とログの該当行を書く

## 手順 9: 報告する

止まった場合も含め、報告ファイルに PR ごとの表を書く。止めた PR には、止めた手順と理由を表の下に書く。まだ手を付けていない PR は「未着手」と書く。

```markdown
| PR | 旧 head | 新 head | PR CI | マージコミット | main CI | 出たタグ |
|---|---|---|---|---|---|---|
| #A | abc1234 | def5678 | success (run 123) | 9f8e7d6 | success (run 456) | v1.2.3 |
| #B | 1111111 | 1111111（取り込みなし） | success (run 124) | 2222222 | success (run 457) | なし |
```

あわせて次を書く: 再実行した run（run id・原因・結果）、ローカルで確認できなかった点、指示から外れた点（なければ「なし」）。

## ルール

- 順番を入れ替えない。前の PR のマージと main の CI が終わるまで次に進まない
- すべての git 操作は worktree の中で行い、オーナーの checkout を変更しない
- 秘密の値（トークン・パスワード）を報告やログに書かない
- 待つときは時間を決めて取り直す。待ちきれなければ止めて報告する
