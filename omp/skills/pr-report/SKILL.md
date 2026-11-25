---
name: pr-report
description: PR の状態・コミット・署名・CI・本文・変更ファイルを gh で確かめ、返信下書きと要約を書く。
---

# pr-report

PR 1 本について、状態・コミット本数・署名・必須チェックの最新 CI・本文・スクショ・変更ファイルを `gh` で自分で取り、返信の下書き（平文）と機械で読める要約を書く。読み取りのみ。書き込みは「本文の直し」の 1 種類だけ。

## 引数

- `/pr-report <owner/repo> #<N>` — 対象の PR
- `head=<sha>` — 期待 head（任意）。全桁で比べる
- `since=<sha>` — コミット本数を「この SHA の次から head まで」でも数える（任意）
- `refs-only=<Issue 番号>[,...]` — 依頼が「本文は `Refs #<Issue>` のみ」と明示しているときだけ渡る（任意）。無ければ本文は直さない
- `shots=<dir>` — スクショを探すディレクトリ（任意）
- `out=<dir>` — 出力先（任意）。なければ `/tmp/pr-report-<owner>-<repo>-<N>-<日時>/`
- 求める証拠（依頼文）— 下記の項目のうち、依頼が挙げたものを必ず入れる。挙がっていなくても、取れる項目は要約に入れる

無人で回るので `ask` はしない。`<owner/repo>` か PR 番号が無ければ止めて報告する。

## 前提条件

- omp 環境
- `gh` CLI（認証済み）、`jq`

## 禁止

PR・Issue へのコメント、レビュー送信、ラベル・draft・base の変更、マージ、close、push、リモートブランチの削除。`gh pr edit` は `--body` だけ、「手順 6」の条件を満たすときだけ。

## 手順

1. **PR の状態を取る**

   ```bash
   gh pr view <N> -R <repo> --json url,title,state,isDraft,baseRefName,headRefName,headRefOid,mergeable,mergeStateStatus,body,statusCheckRollup
   ```

   - `mergeable` が `UNKNOWN` なら 30 秒おきに 5 回まで取り直す
   - `head=` があれば `headRefOid` と全桁で比べる。違っても以降は **実際の head** で取り、要約に不一致を書く（誰かが push した可能性）

2. **コミット本数を数える**（実際の head の SHA で比べる）

   ```bash
   gh api repos/<repo>/compare/<base>...<head> --jq '.total_commits'
   gh api repos/<repo>/compare/<since>...<head> --jq '.total_commits'   # since= があるとき
   ```

   - 後者は `since` の次から head までの本数。`status` が `ahead` 以外（`diverged` など）なら、数えずにその値を書く
   - 一覧は `gh api --paginate -f per_page=100 repos/<repo>/compare/<base>...<head> --jq '.commits[]'`

3. **署名をコミットごとに書く**。2 種類を混ぜない

   - Signed-off-by あり/なし（`git commit -s`）: コミットメッセージに `^Signed-off-by: ` の行があるか
   - GitHub Verified（GPG）: `.commit.verification.verified` が `true` / `false`（`reason` も控える）

   ```bash
   gh api --paginate -f per_page=100 repos/<repo>/compare/<base>...<head> \
     --jq '.commits[] | {sha, signoff: (.commit.message | test("(?m)^Signed-off-by: ")), verified: .commit.verification.verified, reason: .commit.verification.reason}'
   ```

4. **必須チェックごとの最新 CI run を取る**

   - 必須チェックの名前: `gh pr checks <N> -R <repo> --required --json name,state,link`。取れなければ（保護ルールが無い等）`gh api repos/<repo>/branches/<base>/protection/required_status_checks --jq .contexts`。どちらも無ければ、全チェックを対象にして「必須の定義なし」と書く
   - `statusCheckRollup` の同名エントリが複数あれば、`completedAt` / `startedAt` が最も新しいもの（再実行の最新）を使う
   - run id は `detailsUrl` の `/runs/<id>/` から。念のため突き合わせる

     ```bash
     gh run list -R <repo> --commit <head> --json databaseId,name,status,conclusion,createdAt
     ```

   - チェックごとに `name` / `run id` / `status` / `conclusion` を書く。`skipped` は前段の失敗で飛ばされたのか、`if:` による設定上の意図かを区別して書く（`.claude/CLAUDE.md` の `## 完了報告` と同じ）。pending は pending のまま書き、待たない

5. **PR 本文を確かめる**

   - 本文が `Refs #<N>` の行だけ（空行を除く）で構成されているかを見る。それ以外の文（`Closes` / `Fixes` を含む）があれば `body_extra: true` のフラグを立て、その行を要約に抜き出す
   - 依頼が Refs のみと明示していないなら、フラグを立てるだけで直さない

6. **本文の直し**（`refs-only=` があり、手順 5 で `body_extra: true` のときだけ）

   ```bash
   gh pr edit <N> -R <repo> --body 'Refs #<Issue>'
   gh pr view <N> -R <repo> --json body,headRefOid
   ```

   - Issue 番号は `refs-only=` の値だけ。PR 番号や本文から推測した番号を入れない。複数なら `Refs #A` と `Refs #B` を 1 行ずつ（`--body "$(printf 'Refs #A\nRefs #B')"`）
   - 直したあと本文を取り直して一致を確かめ、`headRefOid` が変わっていないことも確かめる。直した事実と直す前の本文を要約に残す

7. **スクショを探す**（`shots=` があるとき）: ディレクトリの `png|jpg|jpeg|webp|gif` を列挙する（パス・件数）。ディレクトリが無ければ「ディレクトリなし」と書く。画像の中身は判定しない（見た結果を書くなら、見たと分かる範囲だけ）

8. **変更ファイルを列挙する**

   ```bash
   gh api --paginate repos/<repo>/pulls/<N>/files --jq '.[] | {filename, status, additions, deletions}'
   ```

## 出力

`out` に 2 ファイルを書く（上書き）。本文直し以外はここにしか書かない。

- `reply.txt` — 日本語の返信下書き。**平文**（マークダウン記法・絵文字を使わない）。**人名・宛名・経緯は書かない**。次の事実だけを短い文で並べる: PR の URL、state・base、head、コミット本数、署名（コミットごと）、必須チェックの結果、本文の状態、スクショの有無、変更ファイル数。確かめていない項目は「未確認」と書く
- `summary.json` — 機械で読める要約

```json
{
  "pr": {"repo": "o/r", "number": 82, "url": "...", "state": "OPEN", "isDraft": false, "base": "main",
         "mergeable": "MERGEABLE", "mergeStateStatus": "CLEAN"},
  "head": {"sha": "<40桁>", "expected": "<40桁|null>", "match": true},
  "commits": {"total": 3, "since": {"sha": "<sha>", "count": 2}, "list": [
    {"sha": "<sha>", "signed_off_by": true, "gh_verified": false, "verified_reason": "unsigned"}]},
  "checks": {"required_defined": true, "items": [
    {"name": "lint", "run_id": 123, "status": "completed", "conclusion": "success", "skipped_reason": null}]},
  "body": {"refs_only": false, "body_extra": true, "extra_lines": ["Closes #1"], "edited": false, "before": null},
  "screenshots": {"dir": "<dir|null>", "count": 0, "files": []},
  "files": [{"filename": "a.md", "status": "added", "additions": 10, "deletions": 0}],
  "unchecked": []
}
```

最後に、出力先のパスと、フラグ（head 不一致・必須チェックの失敗や pending・`body_extra`・署名なし）を 1 行ずつチャットに返す。

## ルール

- 値は報告の文面ではなく、`gh` で自分で取った結果から書く
- 取れなかった項目は空欄にせず `unchecked` に理由を書く
- 秘密の値（トークン・パスワード）を出力に書かない

## 関連

- マージ前の完了確認の考え方: `.claude/skills/omp-done-check`
- OK が出たあとのマージ: `pr-merge`
- 完了報告の書式・skipped の区別: `.claude/CLAUDE.md` の `## 完了報告`
