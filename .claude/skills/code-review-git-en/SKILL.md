---
name: code-review-git-en
description: Code quality check and doc drift detection on git diff against remote.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# code-review-git-en

Ideal for self-review before PR creation or final check before merge.

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- No arguments: Diff between current branch and `origin/develop`
- Branch specified: Compare against specified remote branch (e.g., `origin/main`)

## Phase 1: Diff Retrieval and Analysis

1. `git fetch origin`
2. Determine comparison branch (argument provided -> use it / none -> `origin/develop`)
3. Get merge base (`git merge-base <comparison-branch> HEAD`)
4. Diff file list (`git diff --name-status <merge-base>...HEAD`)
5. Diff stats (`git diff --stat <merge-base>...HEAD`)
6. Commit list (`git log --oneline <merge-base>..HEAD`)
7. Create tasks with TaskCreate

## Phase 2: Code Quality Check (diff only)

Retrieve diffs of changed files and **check focusing on changed areas**. Read surrounding context (full function, etc.) as needed.

Check criteria in `references/check-criteria.md`.

#### Steps
1. Classify changed files (source code, tests, config, docs)
2. Retrieve and check diff for each source file
3. Read full file if surrounding context is needed
4. Check test validity if test files were changed

## Phase 3: Doc Drift Check (docs vs code within diff)

**Cross-reference changes within the diff only.** Do not scan all project docs.

1. Classify diff files (docs: `.md`/`.rst`/`.txt` / code: source and config)
2. Identify code changes that need doc updates (API changes, config changes, structure changes)
3. Identify doc changes that should have corresponding code changes
4. Detect drift:
   - Code changed, no doc update -> missing update
   - Doc changed, no code change -> advance update or unnecessary change
   - Both changed, contradictory -> inconsistency

## Phase 4: Test Execution

Run tests if possible and include results in report.

## Phase 5: Report Generation

1. Confirm output destination with `AskUserQuestion`:
   - **GitHub Issue** (recommended): `review: Git diff review (<branch> -> <comparison>, <YYYY-MM-DD>)`
   - **Local MD**: `code-review-git-report.md`
   - **Console output**: Print the report directly in the conversation
2. Use report format from `templates/report.md`
3. Report summary to user

## Severity Criteria

| Severity | Criteria |
|----------|----------|
| Critical | Security risk, data loss, production incident, docs clearly contradicting spec |
| Important | Bug risk, architecture violation, insufficient tests, missing doc updates |
| Suggestion | Readability/maintainability improvements, refactoring candidates, doc supplements |
| Minor | Naming improvements, code style, wording inconsistencies |

## Rules

- **Focus on diff.** Unchanged code is out of scope (except obvious security risks)
- Never report based on guesses. Verify against actual code and diff
- Always include file path and line number in findings
- Provide concrete improvement suggestions
- Check surrounding context (full function, callers, etc.) for accurate review
- Always include Critical/Important findings. Include Suggestion/Minor only if clear benefit
- Respect project conventions and patterns
- Doc drift check is limited to cross-referencing changes within the diff
- Track progress with TaskCreate/TaskUpdate
