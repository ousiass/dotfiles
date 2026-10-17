# Instructions

## Complexity & readability
- Do not increase complexity without a clear reason.
- Prefer the simplest solution that satisfies the requirements and existing constraints.
- Complexity is allowed only when it reduces overall risk or improves maintainability (e.g., removes duplication, clarifies invariants, improves testability).
- Match the complexity to the task: small tasks should use small, straightforward changes.
- Optimize for readability: clear naming, small functions, and predictable control flow.

## Testing
- Bug fixes must include a regression test:
  - Add a test that fails before the fix and passes after the fix.
  - Place it in the closest relevant test suite.
- テストで非同期処理の完了を待つときは、チャネル・準備完了フック・上限付きの条件待ち（ポーリング）を使い、固定時間の待ち（`time.Sleep` など）に頼らない。
- シグナルを使うテストは、ハンドラの登録後に準備完了を通知させ、その通知を受けてから送る。
- テストが不安定（flaky）になったら、タイムアウトを延ばさず、コード側（待ち方・準備完了の通知）を直す。

## Language
- User-facing responses must use the same language as the instructions used.
- 結論・Summary・最終報告は必ず日本語で書く。識別子・パス・コマンド・エラーメッセージ原文だけ英語のまま残す。

## Asking the user
- 不明点・前提条件が曖昧な点・複数の妥当な選択肢がある場合は、推測で進めずに選択式の確認ツール（Claude Code: `AskUserQuestion` / omp: `ask`）で確認する。テキストだけで質問しない。
- 各選択肢の `description` には判断材料（メリット・デメリット、影響範囲、推奨理由）を簡潔に書く。
- 1回あたり最大4問にまとめる。確認漏れがあれば次のターンで再度その確認ツールを出す。
- すでに明示された指示や、コード/ドキュメントを読めば一意に決まる事項についてはわざわざ聞かない（読んで把握する）。
- 自由入力が必要な場合は、その手段を使う（Claude Code: `AskUserQuestion` の `allowFreeText: true` または「Other」選択肢 / omp: 自由入力を促す選択肢を用意する）。

## Git Commits
- コミットメッセージは `<type>: <説明>` の形式で書く
- type は英語（feat, fix, update, refactor, docs, test など）
- 説明は日本語で簡潔に書く
- 例: `feat: ユーザー認証機能を追加`, `fix: ログイン時のエラーを修正`
- `git commit` / `git push` で `--no-verify` を使わないこと。pre-commit および pre-push フックは必ず通す。フックが失敗した場合はスキップせず、原因を調査・修正する。

## Git Merge
- PR をマージする際は squash せず、マージコミット方式（merge commit）を使うこと。
- `gh pr merge` を使う場合は `--merge` を明示する（`--squash` / `--rebase` は使わない）。
- ローカルで `git merge` する場合も fast-forward ではなく `--no-ff` でマージコミットを残す。

## CI
- PR のあるブランチへ push したら、「完了」と報告する前に CI の結果を確認する。`gh pr checks <PR番号>` で pending が無くなるまで待ち、結果を見ること（ローカルでテストが通っただけでは完了にしない）。
- CI が失敗したら、失敗ジョブのログ（`gh run view --log-failed` など）で原因を調べて直し、同じブランチへ通常の push をする（force push はしない）。タイミング依存のテストなど、再実行で通るだけの失敗でも、原因が分かるなら再実行ではなくコードで直す。
- 報告の形式は `## 完了報告` に従う。
- 指示された範囲を超える操作（ドラフト解除、マージ、コメント、閾値や CI 設定の緩和）が必要になったら、承認を得る前に実行しない（`Asking the user` に従う）。
- 呼び出し元から返答形式（JSON のみ等）や「CI 待ちは呼び出し元が行う」と指示されている場合は、その指示を優先する。

## Push 前の確認
- push する前に、リポジトリの CI 定義（`.github/workflows` など）を読み、同じコマンドをローカルで実行する（build・vet・lint・test など）。実行方法は `## 高負荷ホストでの実行` に従う。
- docker や実機などローカルで再現できない確認は、報告で「未確認」と明記する。

## 高負荷ホストでの実行
- build・vet・lint・test は 1 本のコマンドに詰めず、別々のコマンドで 1 つずつ実行する。
- sweep 系スキルの並列数は既定 5。ホストが高負荷（1 分間の load average が `nproc` を超える）のときは 3 まで下げる。
- 負荷の確認は `uptime`（load average を `nproc` と比べる）。

## 指示の遵守
- 指示で実装方式が決まっている場合は、別の方式に置き換えない。
- 置き換えたい事情が出たら、実装せずに止まって報告し、判断を待つ（`Asking the user` に従う）。
- 呼び出し元から「停止しない」や返答形式（JSON のみ等）と指示されている場合は、その指示を優先し、止まらず failure として返す。
- 指示から外れた点は、`## 完了報告` の欄に書く。

## 完了報告
完了報告には次の欄を、この順で書く（日本語。識別子・コマンドは原文のまま）。
- 対象 PR と head のコミット
- CI の各チェックの結果（成功・失敗・skipped。skipped は前段の失敗で飛ばされたのか、設定上の意図かも添える）
- 指示から外れた点（無ければ「なし」）
- 未確認の点（docker・実機など）
- 次にやること

pending のチェックが残っているのに「CI 確認中」のまま完了と書かない。

呼び出し元から返答形式（JSON のみ等）や「CI 待ちは呼び出し元が行う」と指示されている場合は、その指示を優先する。

## Libraries
- Prefer using well-known, widely adopted libraries when they simplify the solution, reduce risk, or improve maintainability.
- Do not re-implement common, well-solved functionality that a major library already provides (e.g., parsing, validation, date/time handling, HTTP clients), unless there is a clear constraint (performance, bundle size, security policy, dependency restrictions).
- Keep dependencies minimal: introduce a new library only when it provides clear value over standard library or existing dependencies.
- When adding a library, choose a stable option with strong community support and maintenance; document the reason briefly (e.g., in a comment, PR description, or dependency note).

