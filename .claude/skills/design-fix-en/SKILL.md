---
name: design-fix-en
description: Fix design review or design change Issue findings with design verification and PR creation.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# design-fix-en

Fixes findings from `design-review` or `design-request` Issues/reports. Runs design verification after fixes to confirm token compliance and accessibility.

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- **Issue number** (e.g., `/design-fix-en #45`): Fetch design findings from GitHub Issue
- **Issue URL** (e.g., `/design-fix-en https://github.com/owner/repo/issues/45`): Same as above
- **MD file path** (e.g., `/design-fix-en design-review-report.md`): Fetch findings from local report
- **No arguments**: Interview the user

## Phase 1: Retrieve and Organize Findings

1. Retrieve design findings from arguments
   - Issue: Read body and comments via `gh issue view`
   - MD file: Read content via `Read`
   - No arguments: Interview user about what to fix
2. Break down into individual fix items (each: location, current state, expected state)
3. Prioritize by severity (start from Critical)
4. Record the current branch as the base branch
   - Run `git branch --show-current` and display to user: "Base branch: <branch-name>"
   - Retain this name until PR creation in Phase 4
5. Create a working branch
   - Issue: `design/#<issue-number>` (e.g., `design/#45`)
   - Other: `design/<summary>` (e.g., `design/header-spacing-fix`)
6. Create tasks with TaskCreate

## Phase 2: Understand Design Foundation

1. Detect and read project design foundation files:
   - CSS framework config (`tailwind.config.*`, `uno.config.*`, etc.)
   - Design tokens / theme definitions (`theme.ts`, `tokens.*`, `variables.css`, etc.)
   - Global styles (`global.css`, `base.css`, etc.)
   - Existing UI component libraries (shadcn, Vuetify, MUI, etc.)
2. Identify tokens, variables, and components to use during fixes

## Phase 3: Fix Cycle (repeat per finding)

#### 3-1: Examine Target
- Read the target file with `Read` to understand current state accurately

#### 3-2: Fix
- Apply fixes using design foundation tokens/variables
- Avoid hardcoded values; leverage existing tokens
- Use existing components where available

#### 3-3: Design Verification
Verify after each fix:

| Check | What to verify |
|-------|---------------|
| Token compliance | No new hardcoded values introduced |
| Consistency | Unified with other instances of same component |
| Accessibility | ARIA, focus, contrast maintained |
| Responsive | Breakpoint handling not broken |
| Side effects | No unintended impact on other screens using same component |

#### 3-4: Review
- Review the fix with the `review` agent

#### 3-5: Improvement Cycle
- If review issues found -> fix -> re-review -> repeat until no issues

#### 3-6: Format & Lint
- Run format/lint per project settings. Skip if no settings found

#### 3-7: Commit
- Follow commit message conventions in CLAUDE.md
- Separate commits per finding

## Phase 4: Pull Request

1. Confirm all findings are fixed
2. Create PR with `gh pr create --base <base-branch>`
   - **Use the base branch recorded in Phase 1. Never fall back to `main` or `master`.**
   - If unclear, check fork point with `git log --oneline --graph HEAD...main`
   - With Issue: Include Issue number in title, then link via `gh pr edit <PR#> --add-issue <Issue URL>` after creation (do not use Closes keyword)
   - PR body: List of fixed findings (severity, content, summary) + design verification summary
3. Report fix summary to user

## Rules

- Fix only the reported findings. Never mix unrelated refactoring or feature changes
- Prefer tokens/variables over hardcoded values
- Always run design verification (3-3) after each fix
- Always check for side effects (shared component changes must verify impact scope)
- Fix Critical/Important findings. Fix Suggestion/Minor if included in Issue
- Track progress with TaskCreate/TaskUpdate
