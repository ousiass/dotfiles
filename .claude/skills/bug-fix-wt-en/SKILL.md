---
name: bug-fix-wt-en
description: Bug investigation, fix, regression test, and PR creation in an isolated git worktree.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# bug-fix-wt-en

Worktree-isolated version of `bug-fix`. Fixes bugs without affecting the main working tree.

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- **Issue number** (e.g., `/bug-fix-wt-en #42`): Fetch bug report from GitHub Issue
- **Issue URL** (e.g., `/bug-fix-wt-en https://github.com/owner/repo/issues/42`): Same as above
- **Text** (e.g., `/bug-fix-wt-en 500 error on login`): Use text as bug report
- **No arguments**: Interview the user about symptoms

## Phase 1: Bug Report Organization and Worktree Creation

1. Retrieve bug report from arguments
   - Issue: Read body, comments, and labels via `gh issue view`
   - Text: Use as bug report
   - No arguments: Interview the user
2. Organize the following (confirm missing info with user):
   - **Symptoms**: What is happening
   - **Expected behavior**: What should happen
   - **Reproduction steps**: How to reproduce
   - **Environment**: Browser, OS, environment (production/staging/local)
   - **Frequency**: Always / sometimes / under specific conditions
3. Record the current branch as the base branch (PR merge target)
   - Run `git branch --show-current` and display to user: "Base branch: <branch-name>"
   - Retain this name until PR creation in Phase 4
4. Determine the working branch name
   - Issue: `fix/#<issue-number>` (e.g., `fix/#42`)
   - Text / no arguments: `fix/<bug-summary>` (e.g., `fix/login-500-error`)
5. **Create git worktree** (see `references/worktree-setup.md`)
6. Create tasks with TaskCreate

## Phase 2: Root Cause Investigation

**IMPORTANT: All operations from Phase 2 onward must be inside the worktree directory.**

1. **Reproduce** — Follow reproduction steps. If not reproducible, ask user for more info
2. **Identify impact scope** — Search related code with `Explore` agent or `Grep`/`Glob`. Check related tests
3. **Identify root cause** — Pinpoint the root cause with code flow evidence. Report cause and fix plan to user for agreement

## Phase 3: Fix Cycle

#### 3-1: Create Regression Test
- **Before fixing**, create a test that reproduces the bug and confirm it fails

#### 3-2: Fix
- Fix the bug with minimal changes

#### 3-3: Verify
- Confirm regression test + all existing tests pass

#### 3-4: Review
- Review the fix with the `review` agent
- Include worktree path in prompt

#### 3-5: Improvement Cycle
- If review issues found -> fix -> re-review -> repeat until no issues

#### 3-6: Format & Lint
- **Run format/lint inside the worktree directory.** Skip if no settings found

#### 3-7: Commit
- **Run `git add` / `git commit` inside the worktree directory**
- Follow commit message conventions in CLAUDE.md

## Phase 4: Pull Request

1. **Run `git push -u origin <working-branch>` inside the worktree directory**
2. Create PR with `gh pr create --base <base-branch>`
   - **Use the base branch recorded in Phase 1. Never fall back to `main` or `master`.**
   - If unclear, check fork point with `git log --oneline --graph HEAD...main`
   - With Issue: Include Issue number in title, then link via `gh pr edit <PR#> --add-issue <Issue URL>` after creation (do not use Closes keyword)
   - PR body: Bug symptoms, cause, fix summary + manual checklist (see `templates/pr-checklist.md`)
3. Report fix summary and **worktree path** to user

Report example:
```
## Done
- PR: <URL>
- Worktree: <path> (run `git worktree remove <path>` after verification)
```

## Rules

- Never fix by guessing. Identify the root cause before fixing
- Always write a regression test before fixing (test fails -> fix -> test passes)
- Keep fixes minimal. Never mix unrelated refactoring
- Always report cause and fix plan to user for agreement
- Always fix review issues at severity levels. For lower severity, fix only if clear benefit
- Track progress with TaskCreate/TaskUpdate
- **All git/file operations must be inside the worktree directory. Never modify the main working tree.**
