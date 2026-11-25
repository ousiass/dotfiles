---
name: pr-merge
description: OK が出た 1 本の PR を、渡された期待 head と範囲だけでマージし、指定の Issue だけ close する。
---

# pr-merge

OK が出たあとの PR を、期待 head・Issue 一覧・理由・base を渡されたとおりにマージする。どれか 1 つでも合わなければマージせず止めて報告する。無人で回る。

`merge-chain`（複数 PR を順に、衝突の解消と main の CI まで）と `merge-closeout`（確認カードと omp の終了処理まで、Issue は本文から推定）は変えない。これは **1 本の PR を、渡された値だけで** マージする用。

## 引数

- `/pr-merge <owner/repo> #<N> head=<40桁 SHA> base=<branch> issues=<一覧>`
  - `head` — 期待 head（全桁）。ここと違えば止める
  - `base` — PR の base。ここと違えば止める
  - `issues` — close する Issue と理由。`#12:completed #13:not_planned` のように書く。close しないなら `issues=なし` と明示される
- 報告ファイルのパスは依頼文で指定される。なければ `/tmp/pr-merge-<owner>-<repo>-<N>-<日時>.md`

`ask` はしない。引数が 1 つでも欠けている・`head` が 40 桁でない・理由が `completed` / `not_planned` 以外なら、何もせず止めて報告する。

## 前提条件

- omp 環境
- `gh` CLI（認証済み）

## 禁止

`--squash` / `--rebase` / `--admin` / `--auto`、`--delete-branch`（ブランチは消さない）、リリース・デプロイ・タグ、一覧にない Issue の close、Issue・PR へのコメント、マージ失敗や head の変化のあとの再試行、衝突の解消と push、コードの変更。ほかの PR・ブランチには触れない。

## 手順

1. **マージしてよいか確かめる**

   ```bash
   gh pr view <N> -R <repo> --json state,isDraft,isCrossRepository,baseRefName,headRefOid,mergeable,mergeStateStatus,statusCheckRollup
   ```

   次のすべてを満たすときだけ進む。1 つでも外れたら止める（外れた値を報告に書く）

   - `state` が `OPEN`、`isDraft` が `false`
   - `headRefOid` が `head` と全桁で一致（変わっていれば誰かが push した。マージしない）
   - `baseRefName` が `base` と一致
   - `mergeable` が `MERGEABLE`。`UNKNOWN` なら 30 秒おきに 5 回まで取り直す。`CONFLICTING` は止める（解消はしない）
   - `mergeStateStatus` が `BLOCKED` / `DIRTY` でない
   - CI に失敗がない（下記）

2. **CI を確かめる**

   - `statusCheckRollup` の `conclusion` に `FAILURE` / `CANCELLED` / `TIMED_OUT` / `ACTION_REQUIRED` / `STARTUP_FAILURE` があれば止める
   - pending（`status` が `COMPLETED` でない）があれば、30 秒おきに取り直して 30 分まで待つ。待ちきれなければ止める。待つ間に `headRefOid` が変わったら止める
   - `SKIPPED` は、前段の失敗で飛ばされたものなら失敗として止める。`if:` による設定上の意図と確かめられたものだけ許し、理由を報告に書く
   - 判定の材料（チェック名・run id・conclusion）を控える

3. **マージする**

   ```bash
   gh pr merge <N> -R <repo> --merge --match-head-commit <head>
   ```

   - 失敗したら止めて、エラー原文を報告する。やり直さない
   - GitHub が作るマージコミットには Signed-off-by は付かない（`git merge --signoff` は使わない）

4. **マージコミットを確かめる**

   ```bash
   gh pr view <N> -R <repo> --json state,mergeCommit --jq '{state, sha: .mergeCommit.oid}'
   gh api repos/<repo>/commits/<マージコミット> --jq '[.parents[].sha]'
   ```

   - `state` が `MERGED`。親が 2 つで、その片方が `head` と一致することを確かめる（そうでなければ報告に書く）
   - マージコミット SHA と親の SHA を控える

5. **一覧の Issue だけ close する**（1 件ずつ）

   ```bash
   gh issue view <I> -R <repo> --json state,stateReason
   gh issue close <I> -R <repo> --reason completed        # not_planned は "not planned"
   gh issue view <I> -R <repo> --json state,stateReason
   ```

   - すでに `CLOSED` なら飛ばし、そのときの `stateReason` を書く。指定の理由と違うときは、直さず報告に書く
   - `--comment` は付けない。close のあとに状態を取り直し、`CLOSED` と理由を確かめる
   - PR の `closingIssuesReferences`（`gh pr view <N> -R <repo> --json closingIssuesReferences`）に一覧にない Issue があれば、閉じずに「一覧外」として報告する（自動で閉じていたときも同じ）

6. **報告する**

## 報告

報告ファイルに書く。形式は `.claude/CLAUDE.md` の `## 完了報告` に従い、次を含める。止まったときは「マージしていない」と先頭に書く。

- PR と、期待 head・実際の head
- 判定の材料（state・base・mergeable・CI のチェックごとの run id と conclusion）
- マージコミット SHA と親
- Issue ごとの結果（close した / すでに閉じていた〔理由〕/ 一覧外）
- 指示から外れた点（なければ「なし」）。マージ後の main の CI は待たないので「未確認」に書く

## ルール

- マージは 1 回だけ。head・base・CI のどれかが外れたら、その場で止める
- 範囲（Issue の一覧と理由）は渡されたものだけ。本文や参照から足さない
- 秘密の値（トークン・パスワード）を報告に書かない

## 関連

- 確認前の証拠集め: `pr-report`
- 連続マージ: `merge-chain` / 確認カードと omp の終了: `.claude/skills/merge-closeout`
- マージ方式の規則: `.claude/CLAUDE.md` の `## Git Merge`
