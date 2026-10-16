---
name: merge-closeout
description: PR のマージ確認からマージコミットでのマージ、Issue close、omp の終了処理までを行うとき
user-invocable: true
---

# merge-closeout

PR を、確認 → 通常のマージコミットでマージ → 対象 Issue の close → omp の終了処理、の順に片付ける。ほかのボットも使えるように、`omp-pane-report` §12 の流れを独立させたもの。

## 前提条件

- `gh` CLI（認証済み）
- 対象の PR 番号
- `tmux`（omp の終了処理で使う）

## 手順

1. **マージしてよい状態か確認する**

   ```bash
   gh pr view <PR> --json state,isDraft,mergeable,mergeStateStatus,headRefOid,baseRefName,statusCheckRollup
   gh pr checks <PR>
   ```

   - `state` が `OPEN`、`isDraft` が `false`、`mergeable` が `MERGEABLE`
   - CI が全部成功（failure・pending があればマージしない）
   - `headRefOid` が、完了報告で確認した head と一致する（確認の手順は `omp-done-check`）
2. **悠太さんの確認を取る**: 確認カードを出す。PR 番号、head、CI の結果、close する Issue の一覧（下記）を添える。承認が出るまでマージしない
3. **通常のマージコミットでマージする**

   ```bash
   gh pr merge <PR> --merge
   ```

   `--squash` と `--rebase` は使わない。
4. **対象 Issue を手動で close する**: ベースがデフォルトブランチでないと、マージしても Issue は自動で閉じない。

   対象 Issue の一覧の出し方:

   ```bash
   # PR が「Closes #N」などで紐付けている Issue と、本文中の Issue 参照
   gh pr view <PR> --json closingIssuesReferences,body \
     --jq '{closing: [.closingIssuesReferences[].number], body: .body}'
   # 本文中の #N を拾う
   gh pr view <PR> --json body --jq .body | grep -oE '#[0-9]+' | sort -u
   ```

   - 一覧は `closingIssuesReferences` と、本文の `#N` 参照を合わせて作る。本文の参照は「関連」にすぎないものもあるので、close してよいものだけに絞る（迷えば手順 2 の確認カードで聞く）
   - 親 Issue と、そこにぶら下がる子 Issue があるときは、`gh issue view <親> --json body` で子の一覧を確かめ、対象に含めるか決める

   close は 1 件ずつ、完了として閉じる:

   ```bash
   gh issue close <N> --reason completed
   ```

   すでに閉じているものは、`gh issue view <N> --json state` で確かめて飛ばす。
5. **omp を終了する**: omp が動いていたペイン（fish のペイン）へ、貼り付けで送る。**途中経過は報告せず、最終結果だけ伝える**

   1. 作業が終わっているか、15 秒間隔で 2 回確認する

      ```bash
      tmux capture-pane -p -t <PANE> | tail -n 20
      sleep 15
      tmux capture-pane -p -t <PANE> | tail -n 20
      ```

      2 回とも出力が変わらず、`Working` が出ていなければ完了。動いていれば、手順 5.1 をやり直す
   2. `/exit` を送る（貼り付けと Enter は `omp-instruction-card` の手順 4 と同じ）

      ```bash
      printf '/exit' | tmux load-buffer -b omp-closeout -
      tmux paste-buffer -p -d -b omp-closeout -t <PANE>
      sleep 3; tmux send-keys -t <PANE> Enter
      ```
   3. fish のプロンプトに戻ったことを確かめてから、`cd ~` を同じ要領で送る
   4. 続けて `clear` を同じ要領で送る

   `<PANE>` は tmux のペイン指定（`omp-instruction-card` の「ペインの指定」を参照）。

## 最終結果の書式

```
PR #<番号> をマージしました。
- マージ方式: マージコミット（head: <SHA>）
- close した Issue: #<N>, #<M>（completed）／ すでに closed: #<K>
- omp 終了: <ペイン> を /exit → cd ~ → clear 済み
```

## ルール

- マージは `gh pr merge <PR> --merge` だけ。`--squash` / `--rebase` / `--auto` は使わない
- 確認カードの承認なしにマージしない
- Issue の close 理由は `completed` にする
- omp の終了処理の途中経過は報告しない

## 関連

- 元の流れ: `omp-pane-report` §12（かなの私用スキル。このリポジトリの外にある）
- マージ前の完了確認: `omp-done-check`
- ペインへの貼り付け手順: `omp-instruction-card`
