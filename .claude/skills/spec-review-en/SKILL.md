---
name: spec-review-en
description: Review spec documents and fix issues one by one with user confirmation
user-invocable: true
---

# spec-review-en

Review specification documents created by spec-gen, present findings one by one, and fix with user approval.

## Prerequisites

- Claude Code environment
- spec-gen format specs in docs/ or spec/ directory

## Arguments

- No args: auto-detect and review specs
- Path: review specs in specified directory
- Mode: `consistency` `code-drift` `quality` `all`

## Review Modes

| Mode | Description |
|------|-------------|
| **Consistency** | Cross-reference contradictions between spec documents |
| **Code drift** | Detect gaps between implementation code and specs, update specs |
| **Quality** | Format issues, ambiguous descriptions, missing diagrams, stale revision history |
| **All** | Run all 3 modes sequentially |

## Phase 1: Detect and Load Specs

### 1-1: Discover specs

**If path argument provided:**
- Read files/directory at that path directly

**If no argument:**
Search with Glob:
```
**/spec/**/*.md
**/specs/**/*.md
**/docs/**/*.md
**/specifications/**/*.md
**/design/**/*.md
```

If nothing found, ask user for path.

### 1-2: Read all specs

Read all discovered specs to understand current state.

### 1-3: Mode selection

If mode not specified in arguments, ask with `AskUserQuestion`:

```
Question: Which review mode?
Choices:
1. Consistency — cross-reference contradictions between spec documents
2. Code drift — detect gaps between code and specs, update specs
3. Quality — format, ambiguous text, missing diagrams, revision history
4. All — run all 3 modes sequentially
```

## Phase 2: Review

Run review for selected mode(s). For "All": consistency → code drift → quality.

### Consistency checks

| Cross-reference | Check |
|----------------|-------|
| Requirements ↔ API spec | Each feature has corresponding endpoints |
| Requirements ↔ Component design | Each screen has corresponding components |
| ER diagram ↔ API spec | Request/response matches table definitions |
| ER diagram ↔ Requirements | Data used by features is defined as tables |
| Architecture ↔ Non-functional requirements | Tech choices satisfy non-functional requirements |
| Components ↔ API spec | APIs needed by components are defined |

### Code drift checks

Explore implementation code and verify:

| Cross-reference | Check |
|----------------|-------|
| API spec ↔ Routes/handlers | Endpoint paths, methods, parameters match |
| ER diagram ↔ Migrations/models | Table names, columns, types, constraints match |
| Component design ↔ Implementation | Component names, props, dependencies match |
| Architecture ↔ Directory structure | Layer structure, tech choices match reality |

Skip if no code exists, report accordingly.

### Quality checks

| Target | Check |
|--------|-------|
| Mermaid diagrams | Required diagrams present, no syntax errors |
| Revision history | All docs have revision history section with valid dates |
| Ambiguous wording | Vague terms like "as needed", "etc.", "appropriate" |
| Table format | Markdown table formatting is correct |
| Section structure | Heading level consistency, required sections present |
| Link integrity | Cross-references between documents are not broken |

## Phase 3: Present Findings and Fix

Present each finding **one at a time** via `AskUserQuestion`.

### Finding format

```
Question: [Mode] Finding N/M — [filename]

[Description of the issue]
[Quoted excerpt if applicable]
[Proposed fix summary]

Choices:
1. Fix — apply proposed fix
2. Modify fix — specify different fix approach before applying
3. Skip — do not address this finding
4. Fix all remaining — apply all remaining fixes without confirmation
5. End review — discard remaining findings and finish
```

### Applying fixes

- **"Fix"**: Apply fix with Edit
- **"Modify fix"**: Ask for approach via AskUserQuestion with freeText, then apply
- **"Fix all remaining"**: Apply all subsequent fixes without confirmation
- Update revision history on each modified document (increment version, add change description and reason)

## Phase 4: Completion

1. Display fix summary:
   - Finding count per mode
   - Breakdown: fixed / skipped / modified
   - List of modified files
2. Ask via `AskUserQuestion` whether to commit
3. If committing, follow CLAUDE.md conventions

## Rules

- **Always use `AskUserQuestion` with choices for questions.** Never ask via plain text
- Use `allowFreeText: true` when free-form input is needed
- Order findings by severity (high → low)
- Group findings by file (present same-file findings consecutively)
- Edit existing files only. Do not create new files
- Use execution date for revision history dates
- Track progress with TaskCreate/TaskUpdate
