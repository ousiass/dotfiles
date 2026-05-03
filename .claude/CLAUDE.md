# Claude Instructions

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

## Language
- User-facing responses must use the same language as the instructions used.

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

## Libraries
- Prefer using well-known, widely adopted libraries when they simplify the solution, reduce risk, or improve maintainability.
- Do not re-implement common, well-solved functionality that a major library already provides (e.g., parsing, validation, date/time handling, HTTP clients), unless there is a clear constraint (performance, bundle size, security policy, dependency restrictions).
- Keep dependencies minimal: introduce a new library only when it provides clear value over standard library or existing dependencies.
- When adding a library, choose a stable option with strong community support and maintenance; document the reason briefly (e.g., in a comment, PR description, or dependency note).

