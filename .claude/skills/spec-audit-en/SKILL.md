---
name: spec-audit-en
description: Detect unimplemented features, TODOs, skipped tests, and API schema gaps, then create Issues
user-invocable: true
---

# spec-audit-en

Treat spec documents as the Single Source of Truth. Detect implementation gaps and create GitHub Issues.

## Prerequisites

- Claude Code environment
- `gh` CLI (for Issue creation)

## Arguments

- **No arguments**: Auto-discover docs and run full check
- **Path** (e.g., `/spec-audit-en docs/api-spec.md`): Check specific document(s)

## Phase 1: Discovery

If no path argument is given, auto-discover documents from the project root using `Glob`:
- `docs/`, `spec/` directories
- `README.md`, `ARCHITECTURE.md`, `CLAUDE.md`
- OpenAPI/Swagger definitions (`*.yaml`, `*.json`)
- Other `.md` files

Show the discovered document list to the user and confirm the check targets.

**Detection granularity is per function/endpoint**. Report specific items like "DELETE /users/:id is not implemented", not entire sections.

Detection covers all of:
1. **Spec vs Implementation**: Features defined in specs but not implemented
2. **TODO/FIXME/HACK**: Incomplete markers in code
3. **Skipped tests**: `skip`, `pending`, `xit`, `xdescribe`, etc.
4. **API schema gaps**: OpenAPI/Swagger definitions vs actual handlers

## Phase 2: Document Analysis

1. Read target documents determined in Phase 1
2. Extract concrete claims and specifications:
   - Endpoint definitions, function signatures, CLI arguments
   - Data models, table definitions
   - Feature lists, behavior descriptions
   - Config items, environment variables
3. Create tasks with `TaskCreate` to track check targets

## Phase 3: Implementation Cross-check

Refer to `references/check-criteria.md` for detection criteria.

#### 3-1: Spec vs Implementation

1. Extract claims from documents (function names, paths, config values, behaviors) one by one
2. Search for corresponding implementation using `Explore` agent or `Grep`/`Glob`
3. Determine: matches / mismatches / not implemented
4. Record document-side line numbers and implementation-side file:line for mismatches

#### 3-2: TODO/FIXME/HACK

1. `Grep` for `TODO`, `FIXME`, `HACK`, `XXX`, `TEMP`
2. Record each marker's content, file, and line number
3. Link to spec if related

#### 3-3: Skipped Tests

1. `Grep` for:
   - JS/TS: `it.skip`, `describe.skip`, `xit`, `xdescribe`, `test.skip`
   - Go: `t.Skip`
   - Python: `@pytest.mark.skip`, `@unittest.skip`, `self.skipTest`
   - Ruby: `skip`, `pending`
   - Others: adjust based on project language
2. Record skip reason comments, file, and line number

#### 3-4: API Schema Gaps

1. Read OpenAPI/Swagger definitions if present
2. Search for handlers/routes corresponding to defined endpoints
3. Record unimplemented endpoints

## Phase 4: Report Generation and Output

1. Aggregate results by severity (see `references/check-criteria.md`)
2. Generate report using `templates/report.md` format
3. Ask user via `AskUserQuestion` for output destination:
   - **Create GitHub Issues** (Recommended)
   - **Save as local MD file**: Generate `spec-audit-report.md` at project root
   - **Console output**: Display report in conversation

## Phase 5: Issue Creation

When "Create GitHub Issues" is selected:

1. Show a summary list of all findings (title + severity)
2. Ask via `AskUserQuestion` for Issue creation mode:
   - **Single Issue** (Recommended): Combine all findings into one Issue with a checklist
   - **Individual Issues**: Create one Issue per finding
3. Duplicate check: `gh issue list --state open --search "<summary>"` for existing Issues. If duplicate found: ask to skip or create new
4. Issue body follows `templates/issue.md`
5. `gh issue create` with labels: `spec-audit` + severity label (`severity:critical`, `severity:high`, `severity:medium`, `severity:low`)
6. Report created Issue URL(s) to user

## Rules

- Never report gaps based on speculation. **Verify against actual implementation code**
- Show **both** document-side and implementation-side locations for every gap
- Do not modify code. Deliverables are Issues and reports only
- **Always get user approval** before creating Issues
- Track progress with `TaskCreate`/`TaskUpdate`
- When many gaps are found, prioritize severity 🔴🟠; 🟡🟢 may be omitted
