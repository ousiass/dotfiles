---
name: bug-fix-en
description: Systematic bug investigation, root cause analysis, fix, and regression testing.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# bug-fix-en

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- **Issue number** (e.g., `/bug-fix-en #42`): Fetch bug report from GitHub Issue
- **Issue URL** (e.g., `/bug-fix-en https://github.com/owner/repo/issues/42`): Same as above
- **Text** (e.g., `/bug-fix-en 500 error on login`): Use text as bug report
- **No arguments**: Interview the user about symptoms

## Phase 1: Bug Report Organization and Branch Creation

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
4. Create a working branch
   - Issue: `fix/#<issue-number>` (e.g., `fix/#42`)
   - Text / no arguments: `fix/<bug-summary>` (e.g., `fix/login-500-error`)
5. Create tasks with TaskCreate

## Phase 2: Root Cause Investigation

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

#### 3-5: Improvement Cycle
- If review issues found -> fix -> re-review -> repeat until no issues

#### 3-6: Format & Lint
- Run format/lint per project settings. Skip if no settings found

#### 3-7: Commit
- Follow commit message conventions in CLAUDE.md

## Phase 4: Pull Request

1. Create PR with `gh pr create --base <base-branch>`
   - **Use the base branch recorded in Phase 1. Never fall back to `main` or `master`.**
   - If unclear, check fork point with `git log --oneline --graph HEAD...main`
   - With Issue: Include Issue number in title, then link via `gh pr edit <PR#> --add-issue <Issue URL>` after creation (do not use Closes keyword)
   - PR body: Bug symptoms, cause, fix summary + manual checklist (see `templates/pr-checklist.md`)
2. Report fix summary to user

## Rules

- Never fix by guessing. Identify the root cause before fixing
- Always write a regression test before fixing (test fails -> fix -> test passes)
- Keep fixes minimal. Never mix unrelated refactoring
- Always report cause and fix plan to user for agreement
- Always fix review issues at severity levels. For lower severity, fix only if clear benefit
- Track progress with TaskCreate/TaskUpdate
