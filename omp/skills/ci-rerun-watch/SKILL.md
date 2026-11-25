---
name: ci-rerun-watch
description: 失敗した CI のジョブだけを gh run rerun --failed で回し直し、完了まで見守って runner と失敗点を報告する。
---

# ci-rerun-watch

失敗した run のジョブだけを 1 回回し直し、終わるまで見守る。ジョブごとに、どの runner で動いたか・結果・最初に失敗したステップを報告する。**コードは変えない**。直すかどうかの判断は呼び出し元に返す。

## 引数

- `/ci-rerun-watch <owner/repo> <run-id>` — その run を回し直す
- `/ci-rerun-watch <owner/repo> #<PR>` — PR の head の run のうち、失敗しているものを回し直す
- `avoid=<runner 名または label>[,...]` — 当たったら報告するランナー（任意）。runner 名・label のどちらにも一致を見る
- `cancel-on-avoid` — `avoid=` に当たったら run をキャンセルする（依頼があるときだけ付く）
- 報告ファイルのパスは依頼文で指定される。なければ `/tmp/ci-rerun-watch-<owner>-<repo>-<日時>.md`

`ask` はしない。run id も PR も無ければ止めて報告する。

## 前提条件

- omp 環境
- `gh` CLI（認証済み）、`jq`

## 禁止

コード・ブランチ・ワークフローの変更、push、`--failed` なしの全体の再実行、同じ run の 2 回目の再実行、`cancel-on-avoid` がないときのキャンセル、run の削除、`workflow_dispatch`、PR・Issue へのコメント、マージ。

## 手順

1. **対象の run を決める**

   - run id: そのまま使う
   - PR: head を取り、その commit の run を見る（head をここで控える）

     ```bash
     gh pr view <PR> -R <repo> --json headRefOid --jq .headRefOid
     gh run list -R <repo> --commit <head> --json databaseId,name,status,conclusion,attempt
     ```

   - `status` が `completed` でない run は、`gh run watch <id> -R <repo> --interval 30` で終わるまで待つ（`rerun --failed` は完了した run にしか効かない）
   - `conclusion` が `failure` / `timed_out` の run だけを対象にする。対象が 0 件なら、何もせずその旨を報告する

2. **回し直す前を控える**

   ```bash
   gh run view <id> -R <repo> --json attempt,headSha,jobs \
     --jq '{attempt, headSha, failed: [.jobs[] | select(.conclusion=="failure" or .conclusion=="timed_out") | {name, databaseId}]}'
   ```

3. **回し直す**（run ごとに 1 回だけ）

   ```bash
   gh run rerun <id> -R <repo> --failed
   ```

   - 失敗したら止めて、エラー原文を報告する（再試行しない）
   - 次の attempt（控えた `attempt` + 1）が `queued` / `in_progress` になるまで 10 秒おきに 2 分まで取り直す: `gh run view <id> -R <repo> --json attempt,status`

4. **完了まで見守る**（30 秒おき、上限 2 時間）

   - 毎回、その attempt の job を取り、runner を確かめる（手順 5）。`avoid=` に当たるものがあれば下記「避けるランナー」に従う
   - `status` が `completed` になったら手順 6 へ。上限を超えたら「未完了」として、その時点の状態を報告する

   ```bash
   gh api repos/<repo>/actions/runs/<id>/attempts/<attempt>/jobs --paginate \
     --jq '.jobs[] | {id, name, status, conclusion, runner_name, runner_group_name, labels, steps: [.steps[] | {number, name, conclusion}]}'
   ```

5. **runner を控える**

   - 名前: `runner_name`（`queued` の間は `null`。割り当て後に取り直す）。group: `runner_group_name`
   - labels: `labels`（`runs-on` で要求した label）
   - OS: labels に `Linux` / `macOS` / `Windows`、または `ubuntu-*` / `macos-*` / `windows-*` があればそこから。決まらなければジョブログの先頭（`Set up job`）の `Operating System` を見る。それでも分からなければ「不明」と書く（推測しない）

6. **最初に失敗したステップと要点のエラー行を取る**（`conclusion` が `failure` / `timed_out` のジョブごと）

   - 最初に失敗したステップ: `steps` のうち `conclusion` が `failure` で `number` が最小のもの
   - エラー行: ジョブログから `##[error]` の行と、その直前の数行を取る。報告には 1 ジョブにつき要点 3 行までにする

   ```bash
   gh api repos/<repo>/actions/jobs/<job-id>/logs | sed -E 's/^[0-9T:.Z-]+ //' | grep -n -B3 '##\[error\]' | head -20
   ```

   - ツール導入・ネットワークの失敗（`proxy.golang.org` への接続、パッケージ取得、runner のセットアップ）と、コードの失敗（テスト・lint・ビルド）は分けて書く。分類できなければ「不明」と書く

7. **報告する**

## 避けるランナー

`avoid=` の名前・label のどれかに、ジョブの `runner_name` / `labels` が一致したら、そのジョブを見つけた時点で報告に書く（job 名・runner 名・labels・時刻）。

- `cancel-on-avoid` があれば `gh run cancel <id> -R <repo>` でその run をキャンセルし、キャンセルしたことと時刻を書く。キャンセルは run 全体に効く（ジョブ単位ではない）。キャンセルのあとは、再実行せず止める
- `cancel-on-avoid` がなければキャンセルせず、見守りを続けて完了後の報告に含める

## 報告

報告ファイルに書く。形式は `.claude/CLAUDE.md` の `## 完了報告` に従い、run ごとに次を含める。

```markdown
run <id>（<workflow 名>）attempt <前> → <後> / head <sha>

| job | runner（名前 / group） | labels | OS | conclusion | 最初に失敗したステップ | 要点のエラー行 |
|---|---|---|---|---|---|---|
| test (ubuntu-latest) | GitHub Actions 3 / GitHub Actions | ubuntu-latest | Linux | failure | Run make test | `##[error]Process completed with exit code 2.` |
```

- 回し直す前に失敗していたジョブと、回し直した後の結果の対応（直った / また失敗 / 未完了）
- 避けるランナーに当たったか（当たった job・runner・キャンセルしたか）
- 指示から外れた点（なければ「なし」）

回し直しても失敗したときは、もう 1 回回さず、分類（ネットワーク・ツール導入／コード／不明）とログの該当行を添えて呼び出し元に返す。

## ルール

- 再実行は run ごとに 1 回。回し直す対象は失敗したジョブだけ
- 値は `gh` で取った結果から書く。取れなかった項目は「不明」と理由を書く
- 秘密の値（トークン・パスワード）をログの引用に含めない。含まれていたら伏せ字にする

## 関連

- 失敗の扱いを決める連続マージ: `merge-chain` の「CI の失敗の扱い」
- CI を確かめて完了にする側: `.claude/skills/omp-done-check`
- 失敗を直す方針: `.claude/CLAUDE.md` の `## CI`
