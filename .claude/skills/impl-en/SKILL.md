---
name: impl-en
description: Iterative implementation cycle with scope splitting, develop, review, commit, and PR creation.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# impl-en

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- **Issue number** (e.g., `/impl-en #123`): Fetch requirements from GitHub Issue
- **Issue URL** (e.g., `/impl-en https://github.com/owner/repo/issues/123`): Same as above
- **Text** (e.g., `/impl-en Add user authentication`): Use text as requirements
- **No arguments**: Interview the user for requirements

## Forbidden Actions (Critical)

If any of the following occurs, redo that phase. Skipping for "context savings" or "small change" is not accepted.

- Skipping any sub-step (2-1 to 2-6) with "later", "leave as TODO", or "separate PR"
- Silently skipping a phase or sub-step without declaring it to the user
- Committing with unimplemented tests or dummy assertions (e.g., `expect(true).toBe(true)`)
- Self-reviewing instead of calling the `review` agent
- Skipping lint/format without attempting to run (skipping is allowed only after running and confirming no settings exist)

If scope reduction is needed, redo Phase 1 scope splitting and confirm with the user instead of skipping phases.

If you discover **work independent of the current scope** during implementation (unrelated bugs, out-of-scope improvements, refactors that need their own PR), do NOT leave them as TODOs — split them out via `/spinoff-issue-en --parent <parent issue#> <summary>` and continue the current scope. Always pass the parent Issue number recorded in Phase 1 via `--parent` (omit only when there is no parent issue, e.g. text-driven runs).

## Phase 1: Requirements Analysis and Scope Splitting

1. Retrieve requirements from arguments
   - Issue: Read body and comments via `gh issue view`
   - Text: Use as-is
   - No arguments: Interview the user
2. Check for spec documents
   - If CLAUDE.md specifies the spec location, follow it
   - Otherwise, search broadly with Glob (`**/SPEC.md`, `**/spec/**`, `docs/**`, etc.)
   - Read any documents linked in the Issue body
   - Cross-reference spec contents with requirements and use as implementation input
   - If no spec found, proceed as-is
3. Record the current branch as the base branch (PR merge target)
   - Run `git branch --show-current` and display to user: "Base branch: <branch-name>"
   - Retain this name until PR creation in Phase 3
4. Determine the working branch (see `references/branch-naming.md`)
5. Split requirements into independently implementable and testable units
6. Sort by dependencies and determine implementation order
7. Create tasks with TaskCreate

- Explore and understand the codebase to grasp requirements accurately
- Confirm unclear specs with the user
- Confirm backward compatibility with the user if breaking changes exist

## Phase 2: Implementation Cycle (repeat per scope)

**Set the current scope task to `in_progress` via `TaskUpdate` at the start of each scope.**

#### 2-1: Plan
- Create an implementation plan with the `Plan` agent
- Clarify change locations, impact scope, and test requirements

#### 2-2: Develop
- Implement (including tests) with the `develop` agent
- Satisfy requirements with minimal changes
- **Write production-ready code. The following do NOT count as complete implementation:**
  - Tests containing only mocks/stubs with no real code
  - Functions filled with `TODO`, `NotImplementedError`, `pass`, or `throw new Error("not implemented")`
  - Interface/type definitions only with no actual implementation

#### 2-3: Review
- Code review with the `review` agent
- Evaluate requirement conformance, code quality, and test sufficiency
- **Incomplete implementation check**: Verify no mock/stub-only code, TODO/NotImplementedError placeholders, or empty function bodies

#### 2-4: Improvement Cycle
- If review issues found -> fix with `develop` -> re-review -> repeat until no issues

#### 2-5: Format & Lint
- Run format/lint on changed files per project settings
- Skip if no settings found

#### 2-6: Commit (mandatory)
- **Commit at each scope completion. Never skip.**
- Follow commit message conventions in CLAUDE.md
- **After committing, set the task to `completed` via `TaskUpdate`**

## Phase 3: Final Verification and PR Creation

1. Confirm all scopes are implemented
2. Run full test suite
3. Create PR with `gh pr create --base <base-branch>`
   - **Use the base branch recorded in Phase 1. Never fall back to `main` or `master`.**
   - If unclear, check fork point with `git log --oneline --graph HEAD...main`
   - With Issue: Include Issue number in title, then link via `gh pr edit <PR#> --add-issue <Issue URL>` after creation (do not use Closes keyword)
   - PR body: Change summary + manual checklist (see `templates/pr-checklist.md`)
4. Report implementation summary to user

## Rules

- Each scope must be independently implementable and testable
- **Commit at each scope completion.** Never proceed without committing
- Fix review issues at all severity levels
- Track progress with TaskCreate/TaskUpdate
- **Phase declaration**: At the start of each sub-step (2-1 to 2-6) display `▶ 2-X start: <name>`, and on completion display `✓ 2-X done`. This prevents silent skipping.
- **Self-check**: Before completing each phase, re-read the corresponding section of this SKILL.md and verify no steps were skipped before moving to the next phase.
- On compaction (context compression), check current progress with `TaskList` before resuming work
