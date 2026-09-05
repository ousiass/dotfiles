---
name: impl-wt-en
description: Implementation cycle in an isolated git worktree environment with PR creation.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# impl-wt-en

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI
- `jq`

## Arguments

- **Issue number** (e.g., `/impl-wt-en #123`): Fetch requirements from GitHub Issue
- **Issue URL** (e.g., `/impl-wt-en https://github.com/owner/repo/issues/123`): Same as above
- **Text** (e.g., `/impl-wt-en Add user authentication`): Use text as requirements
- **No arguments**: Interview the user for requirements

## Forbidden Actions (Critical)

If any of the following occurs, redo that phase. Skipping for "context savings" or "small change" is not accepted.

- Skipping any sub-step (2-1 to 2-7) with "later", "leave as TODO", or "separate PR"
- Silently skipping a phase or sub-step without declaring it to the user
- Committing with unimplemented tests or dummy assertions (e.g., `expect(true).toBe(true)`)
- Self-reviewing instead of calling the `review` agent
- **Committing without running the 2-6 verification gate, or committing while it reports FAIL** (never substitute your own judgement for the gate; "it is obviously fixed, so the gate is unnecessary" is forbidden)
- **Weakening what is being verified in order to pass the gate** (deleting tests, weakening assertions, overusing `verify-scope: allow`, disabling lint rules). Fix the implementation, not the gate
- Skipping lint/format without attempting to run (skipping is allowed only after running and confirming no settings exist)
- **Deferring out-of-scope findings to "report later", "list in PR body", or "mention in final summary"** (anything short of appending to `.sweep/spinoff-draft.jsonl` on the spot is a violation; writing "discovered but not filed" in the PR body or final report is itself forbidden)
- **Calling `/spinoff-issue-en` individually per finding** (filing is consolidated into the single `--batch` call at Phase 3)

If scope reduction is needed, redo Phase 1 scope splitting and confirm with the user instead of skipping phases.

If you discover **work independent of the current scope** during implementation (unrelated bugs, out-of-scope improvements, refactors that need their own PR), **append one line to `.sweep/spinoff-draft.jsonl` inside the worktree directory the moment you notice**:

```bash
mkdir -p .sweep
jq -nc --arg parent "<parent issue#>" --arg type "<bug|feat|chore|refactor|docs>" \
       --arg title "<summary>" --arg files "<file:line>" --arg why "<why it is not mixed into this scope>" \
       '{parent:$parent, type:$type, title:$title, files:$files, why:$why}' >> .sweep/spinoff-draft.jsonl
```

**Do not create the issue here** (do not call `/spinoff-issue-en`). Filing happens once, in bulk, at Phase 3. The "gets forgotten / substituted by a PR-body list" failure is prevented by the file, so on-the-spot filing is unnecessary. **Deferring the append itself is still forbidden** (recalling findings at the end of a sub-step or scope is not allowed). Always put the parent Issue number recorded in Phase 1 into `parent` (empty string only when there is no parent issue, e.g. text-driven runs). `.sweep/` is a working-file directory — never include it in a commit.

## Phase 1: Requirements Analysis and Scope Splitting

1. Retrieve requirements from arguments
   - Issue: Read body and comments via `gh issue view`
     - Inspect the fetched `assignees`. **If any assignee other than yourself is already set, name them and ask the user whether it is OK to proceed while someone else is assigned.** Only continue after explicit approval; otherwise stop here.
     - After the check passes, run `gh issue edit <issue#> --add-assignee @me` to add yourself as an assignee (marks work-in-progress; existing assignees are preserved and this is a no-op if you are already assigned)
   - Text: Use as-is
   - No arguments: Interview the user
2. **Load the repo profile** (spec: `references/repo-profile.md` in `impl`)
   - Get the path with `~/.claude/skills/impl/scripts/verify-scope.sh --profile-path`
   - If it exists and none of the invalidation conditions apply (see that reference), **use it as-is and perform no exploration**
   - Generate it only when missing or stale (test / lint / format commands, spec paths, test layout convention, package manager)
   - **The profile is keyed by the git common dir, so every worktree of the same repository shares it.** Do not re-explore each time a worktree is created
3. Check for spec documents
   - Read the profile's `spec_paths`. Also read any documents linked in the Issue body
   - Cross-reference spec contents with requirements and use as implementation input
   - If no spec found, proceed as-is
4. Record the current branch as the base branch (PR merge target)
   - Run `git branch --show-current` and display to user: "Base branch: <branch-name>"
   - Retain this name until PR creation in Phase 3
5. Determine the working branch name (see `references/branch-naming.md`)
6. **Create git worktree** (see `references/worktree-setup.md`)
7. **Build the context pack** (spec: `references/context-pack.md` in `impl`)
   - **Inside the worktree directory**, and **without spawning a subagent**, gather "similar implementations / conventions of this layer / files to touch / how tests are written" with Grep / Glob / Read, under fixed headings and within 60 lines
   - Embed this pack in every 2-1 / 2-2 / 2-3 prompt
8. Split requirements into independently implementable and testable units, and **tag each scope with a type (`fix` / `feat` / `refactor` / `docs` / `test` / `chore`)**
   - The type is passed to the 2-6 verification gate. **Any scope that fixes a bug is `fix`** (regression-test presence is checked mechanically)
9. Sort by dependencies and determine implementation order
10. Create tasks with TaskCreate

- Explore and understand the codebase to grasp requirements accurately
- Confirm unclear specs with the user
- Confirm backward compatibility with the user if breaking changes exist

## Phase 2: Implementation Cycle (repeat per scope)

**IMPORTANT: Specify the worktree path as working directory in all subagent calls during Phase 2.**

**Set the current scope task to `in_progress` via `TaskUpdate` at the start of each scope.**

#### 2-1: Plan
- Create an implementation plan with the `Plan` agent
- Clarify change locations, impact scope, and test requirements
- Include the worktree path and the context pack in the prompt

#### 2-2: Develop
- Implement (including tests) with the `develop` agent
- Satisfy requirements with minimal changes
- Include the worktree path and the context pack in the prompt
- **Honour fail-first for `fix` scopes**: write a test that reproduces the defect, **confirm it fails**, then fix it and make it green. If the test passes from the start, it does not reproduce the defect — rewrite it
- **Write production-ready code. The following do NOT count as complete implementation:**
  - Tests containing only mocks/stubs with no real code
  - Functions filled with `TODO`, `NotImplementedError`, `pass`, or `throw new Error("not implemented")`
  - Interface/type definitions only with no actual implementation

#### 2-3: Review
- Code review with the `review` agent (shape the prompt as in `templates/review-prompt.md` in `impl`)
- Evaluate requirement conformance, code quality, and test sufficiency
- Include worktree path in prompt
- **Incomplete implementation check**: Verify no mock/stub-only code, TODO/NotImplementedError placeholders, or empty function bodies

#### 2-4: Improvement Cycle
- If review issues found -> fix with `develop` -> re-review -> repeat until no issues
- **From the second round on, always attach the "Previous findings and what was done" section from `templates/review-prompt.md` in `impl`** (without it, review repeats the same finding and develop repeats the same fix)

#### 2-5: Format & Lint
- Run format/lint on changed files per project settings (the profile's `format_cmd`)
- **Run format/lint commands inside the worktree directory**
- Skip if no settings found

#### 2-6: Verification Gate (mandatory)
- **Always run before committing. Never skip.**
- **Run it inside the worktree directory** (the script targets the repository root of the directory it runs in)

```bash
~/.claude/skills/impl/scripts/verify-scope.sh --type <type of this scope>
```

- Four checks: unimplemented patterns in added lines / regression test presence for `fix` scopes / test exit code / lint exit code
- **Do not commit until it exits 0.** When FAIL is reported:
  1. Pass the FAIL output (test log, offending `file:line`) **verbatim** to `develop` and have it fixed
  2. Re-run the gate. **Repeat with no iteration limit until it is green**
  3. **If the same FAIL occurs twice in a row, stop repeating the same fix.** On the third `develop` call, state explicitly what was already tried and that it did not work, and require a different approach. If the same FAIL still persists, first isolate the cause (a wrong test / environment dependency / contradictory requirements) before resuming
- You may fix a test only when the FAIL genuinely stems from the test itself. **Deleting or weakening tests to pass the gate is forbidden** (see Forbidden Actions)
- WARN (e.g. skipped tests) does not block the commit, but report its content in one line

#### 2-7: Commit (mandatory)
- **Commit at each scope completion. Never skip.**
- **Requires 2-6 to have exited 0**
- **Run `git add` / `git commit` inside the worktree directory**
- Follow commit message conventions in CLAUDE.md
- **After committing, set the task to `completed` via `TaskUpdate`**

## Phase 3: Final Verification and PR Creation

1. Confirm all scopes are implemented
2. **Run full test suite inside the worktree directory**
3. **Bulk-file out-of-scope findings**: If `.sweep/spinoff-draft.jsonl` exists and is non-empty, call `/spinoff-issue-en --batch .sweep/spinoff-draft.jsonl` **exactly once** to file them all, then delete the draft. Also explicitly verify and declare that no finding is missing from the draft (append it first, then file). Writing "discovered but not filed" in the PR body or final report is forbidden.
4. **Run `git push -u origin <working-branch>` inside the worktree directory**
5. Create PR with `gh pr create --base <base-branch>`
   - **Use the base branch recorded in Phase 1. Never fall back to `main` or `master`.**
   - If unclear, check fork point with `git log --oneline --graph HEAD...main`
   - With Issue: Include Issue number in title, then link via `gh pr edit <PR#> --add-issue <Issue URL>` after creation (do not use Closes keyword)
   - PR body: Change summary + manual checklist (see `templates/pr-checklist.md`)
6. Report implementation summary and **worktree path** to user

Report example:
```
## Done
- PR: <URL>
- Worktree: <path> (run `git worktree remove <path>` after verification)
```

## Rules

- Each scope must be independently implementable and testable
- **Commit at each scope completion.** Never proceed without committing
- Fix review issues at all severity levels
- Track progress with TaskCreate/TaskUpdate
- **Phase declaration**: At the start of each sub-step (2-1 to 2-7) display `▶ 2-X start: <name>`, and on completion display `✓ 2-X done`. This prevents silent skipping.
- Report the 2-6 result in one line as well (`✓ 2-6 done: FAIL 0 / WARN 1`)
- **Self-check**: Before completing each phase, re-read the corresponding section of this SKILL.md and verify no steps were skipped before moving to the next phase.
- On compaction (context compression), check current progress with `TaskList` before resuming work
- **All git/file operations must be inside the worktree directory. Never modify the main working tree.**

## Bundled Files

| File | When it is used |
|---|---|
| `scripts/verify-scope.sh` in `impl` | 2-6 (verification gate), Phase 1 step 2 (`--profile-path`) |
| `references/repo-profile.md` in `impl` | Phase 1 step 2 (generating / invalidating the profile) |
| `references/context-pack.md` in `impl` | Phase 1 step 7 (how to build the pack) |
| `templates/review-prompt.md` in `impl` | 2-3 / 2-4 |
| `references/branch-naming.md` | Phase 1 step 5 |
| `references/worktree-setup.md` | Phase 1 step 6 |
| `templates/pr-checklist.md` | Phase 3 step 5 |
