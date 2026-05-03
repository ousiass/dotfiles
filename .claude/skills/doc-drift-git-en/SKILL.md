---
name: doc-drift-git-en
description: Check doc-code consistency on git diff against remote and generate drift report.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# doc-drift-git-en

**Cross-reference changes within the diff only.** Does not scan all project docs.
Ideal for checking doc update omissions before PR creation.

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- No arguments: Diff between current branch and `origin/develop`
- Branch specified: Compare against specified remote branch (e.g., `origin/main`)

## Phase 1: Diff Retrieval and Classification

1. `git fetch origin`
2. Determine comparison branch (argument provided -> use it / none -> `origin/develop`)
3. Get merge base (`git merge-base <comparison-branch> HEAD`)
4. Diff file list (`git diff --name-status <merge-base>...HEAD`)
5. Commit list (`git log --oneline <merge-base>..HEAD`)
6. Classify diff files:
   - **Docs**: `.md`, `.rst`, `.txt` (README, docs/, spec/, etc.)
   - **Code**: Source code, config, migrations, dependency definitions
   - **Other**: Images, binaries, etc. (out of scope)
7. Check if both docs and code are included in the diff
8. Create tasks with TaskCreate

## Phase 2: Doc Diff Analysis

Retrieve diffs for each document, extract added/changed/deleted statements. Identify what they relate to (API, config, structure, etc.).

## Phase 3: Code Diff Analysis

Identify code changes that need doc updates. Check criteria in `references/check-criteria.md`.

## Phase 4: Cross-reference and Drift Detection

| Pattern | State | Typical severity |
|---------|-------|-----------------|
| Code changed, no doc update | Missing update | Critical to Suggestion depending on impact |
| Doc changed, no code change | Advance update or unnecessary change | Suggestion to Minor |
| Both changed, contradictory | Inconsistency | Critical to Important |
| Both changed, consistent | Normal | — |

#### Steps
1. For each "needs doc update" code change, check if corresponding doc update exists in diff
2. For each doc change, check if corresponding code change exists in diff
3. For changes in both, verify consistency
4. Record drift with specific locations (code file:line and doc file:line)

## Phase 5: Report Generation

1. Confirm output destination with `AskUserQuestion`:
   - **GitHub Issue** (recommended): `review: Doc drift report (<branch> -> <comparison>, <YYYY-MM-DD>)`
   - **Local MD**: `doc-drift-git-report.md`
   - **Console output**: Print the report directly in the conversation
2. Use report format from `templates/report.md`
3. Report summary to user

## Severity Criteria

| Severity | Criteria |
|----------|----------|
| Critical | API/data model/auth changes without doc updates, or clear contradictions |
| Important | Config/dependency/setup changes without doc updates |
| Suggestion | Minor feature change omissions, doc supplements that improve UX |
| Minor | Wording inconsistencies, outdated version numbers, trivial inaccuracies |

## Rules

- **Focus on diff.** Docs and code not in the diff are out of scope
- Never report drift based on guesses. Verify against actual diff
- Show both code-side and doc-side locations for each drift
- Report facts only. Leave fix decisions to the user
- Check surrounding context (full function, callers, etc.) for accuracy
- Always include Critical/Important findings. Include Suggestion/Minor only if clear benefit
- Code comments and docstrings are out of scope
- Track progress with TaskCreate/TaskUpdate
