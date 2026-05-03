---
name: doc-drift-en
description: Check documentation vs implementation code consistency and generate drift report.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# doc-drift-en

**Treat specifications as the source of truth (Single Source of Truth).** Report drift as implementation-side issues by default.

## Prerequisites

- Claude Code environment
- `gh` CLI (for GitHub Issue output)

## Arguments

- No arguments: Check the entire project in the current directory
- Path specified: Check only the specified documents or directories

## Phase 1: Document Discovery

1. Search from project root:
   - `README.md` (root and major directories)
   - Under `docs/`, `spec/`
   - `ARCHITECTURE.md`, `CONTRIBUTING.md`, `CHANGELOG.md`, `CLAUDE.md`
   - Other `.md` / `.rst` / `.txt` files
2. Read each document and understand claims/specifications
3. If no documents found, confirm with user
4. Create tasks with TaskCreate

## Phase 2: Cross-reference with Implementation

Cross-reference each document against check criteria (see `references/check-criteria.md`).

#### Steps

1. Extract concrete claims from documents (function names, paths, config values, behaviors, etc.)
2. Search for corresponding implementation code with `Explore` agent or `Grep`/`Glob`
3. Compare claims with implementation; determine match or mismatch
4. Record mismatches with specific locations (document line and implementation file:line)

## Phase 3: Report Generation

1. Confirm output destination with `AskUserQuestion`:
   - **GitHub Issue** (recommended): Title `review: Doc drift report (<branch>, <YYYY-MM-DD>)`
   - **Local MD file**: `doc-drift-report.md`
   - **Console output**: Print the report directly in the conversation
2. Use report format from `templates/report.md`
3. Report summary to user

## Rules

- Never report drift based on guesses. Verify against actual code
- Show both document-side and implementation-side locations for each drift
- Report facts only. Leave fix decisions to the user
- Treat specs as source of truth, but if implementation is correct and spec is outdated, recommend "update spec"
- Always include Critical/Important findings. Include Suggestion/Minor only if clear benefit
- Code comments and docstrings are out of scope
- Track progress with TaskCreate/TaskUpdate
