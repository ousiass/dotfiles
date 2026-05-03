---
name: code-review-en
description: Full codebase quality check and refactoring review with report generation.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# code-review-en

## Prerequisites

- Claude Code environment
- `gh` CLI (for GitHub Issue output)

## Arguments

- No arguments: Check the entire project in the current directory
- Path specified: Check only the specified directory or file

## Phase 1: Project Structure Analysis

1. Identify directory structure, languages, and frameworks
2. Determine frontend / backend / both
3. List target files (exclude `.gitignore` entries and build artifacts)
4. Identify applicable check criteria and create tasks with TaskCreate

## Phase 2: Quality Check

Run all applicable check criteria based on the detected project structure.
**Check all target files.** Split by directory if there are many files.

Check criteria details in:
- Common: `references/check-common.md`
- Linterly: `references/check-linterly.md`
- Frontend: `references/check-frontend.md` (includes Atomic Design rules)
- Backend: `references/check-backend.md`
- Refactoring: `references/check-refactoring.md`

## Phase 3: Report Generation

1. Confirm output destination with `AskUserQuestion`:
   - **GitHub Issue** (recommended): Title `review: Code quality report (<branch>, <YYYY-MM-DD>)`
   - **Local MD file**: `code-review-report.md`
   - **Console output**: Print the report directly in the conversation
2. Use report format from `templates/report.md`
3. Report summary to user

## Severity Criteria

| Severity | Criteria |
|----------|----------|
| Critical | Security risk, data loss, production incident |
| Important | Architecture violation, missing layer separation, untestable structure |
| Suggestion | Readability/maintainability improvements, refactoring candidates |
| Minor | Naming improvements, code style, trivial improvements |

## Rules

- Never report based on guesses. Verify against actual code
- Always include file path and line number in findings
- Provide concrete improvement suggestions
- Always include Critical/Important findings. Include Suggestion/Minor only if clear benefit
- Respect framework conventions and existing code style
- Track progress with TaskCreate/TaskUpdate
