---
name: spec-gen-en
description: Interactively create design documents for new projects. Also supports appending to existing specs.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# spec-gen-en

Actively discuss with the user to resolve unknowns, presenting reference ideas to solidify specifications.

## Prerequisites

- Claude Code environment
- `gh` CLI (for GitHub Issue mode)

## Arguments

- No arguments: Create a full set of design documents for a new project
- Path specified: Append/update to an existing specification document

## Documents to Generate (Default Paths)

| Document | Default File | Content |
|----------|------|---------|
| **Functional requirements** | `docs/requirements/functional.md` | Use cases, feature list, screen/operation flows |
| **Non-functional requirements** | `docs/requirements/non-functional.md` | Performance, security, availability, scalability |
| **Architecture design** | `docs/architecture/overview.md` | Overall structure, tech stack, layer architecture, communication flows |
| **ER / Data model** | `docs/architecture/er.md` | Overall ER diagram, per-table ER diagrams, table definitions, constraints, indexes |
| **API specification** | `docs/api/endpoints.md` | Endpoints, request/response, auth, errors |
| **Component design** | `docs/components/overview.md` | Component breakdown, responsibilities, dependencies, interfaces |

- **These are default paths. If an existing spec directory is found, use that instead (see "Discovery" below)**

## Phase 1: Assess Current State and Decide Direction

#### 1-0: Discover Existing Specs (Required — Run First)

**If a path is specified as argument:**
- Read the file/directory at that path directly
- Also check related files in the same directory

**If no argument:**
Search for existing specs using Glob:
```
**/spec/**/*.md
**/specs/**/*.md
**/docs/**/*.md
**/specifications/**/*.md
**/design/**/*.md
```

**Based on discovery results:**
- **Existing specs found**: Record the directory structure and file paths as the base map. Place new documents within this structure. Do NOT use default paths
- **No specs found**: Use default paths (`docs/` subtree)

**Important: Always Read discovered spec files to understand current specifications before proceeding.**

#### Output Destination

Confirm with `AskUserQuestion`:
- **GitHub Issue + branch** (recommended): Create the implementation Issue, then use its number for the work branch. The same Issue can be passed to `impl` at the end
- **Local only**: Work on current branch without creating Issues or branches

#### For New Projects
1. Interview about overview, purpose, and background
2. Present similar projects and tech stack direction
3. Agree on document scope
4. **GitHub Issue mode**: Record base branch -> **create placeholder Issue** -> create `feat/#<issue-number>` branch -> add branch name to Issue
   - **Issue title must be `feat: <feature-name>`** (the feature to implement). Never use document-centric titles like "Create design documents"
   - **Body is a placeholder at this point** (e.g., `仕様策定中（spec-gen 実行中）。完了後に実装内容を追記する。`). Phase 3 rewrites it as the implementation Issue
   - Spec creation itself is the work of this skill, not a separate Issue. The goal here is to reserve an Issue number that will be reused as the impl target
5. Create tasks with TaskCreate

#### For Appending to Existing Specs
1. **Using 1-0 discovery results**, Read all existing spec files to understand current specifications
2. Interview about additions
3. Present existing feature reuse/change proposals
4. Agree on direction
5. **GitHub Issue mode**: Same as above (Issue title describes the feature to add; body is a placeholder)
6. Create tasks with TaskCreate

## Phase 2: Document Creation Cycle (repeat per document)

#### 2-1: Interview
- Gather information needed for the document in **a single `AskUserQuestion` call**
- Include pros/cons and reference ideas in option `description` fields

#### 2-2: Write
- Create based on interview results. Use Mermaid for diagrams (see `references/mermaid-guide.md`)
- Include revision history (see format at end of `references/mermaid-guide.md`)

#### 2-3: Review
- Present to user and confirm with `AskUserQuestion` (include "No issues" option)

#### 2-4: Improvement Cycle
- If feedback -> revise -> update revision history -> re-confirm -> repeat until satisfied

#### 2-5: Format & Lint
- Run if settings exist. Skip otherwise

#### 2-6: Commit
- Commit following CLAUDE.md conventions

## Phase 3: Finalize and Push

1. Confirm all documents are complete
2. Cross-document consistency check (ER vs API, components vs functional requirements, etc.)
3. **GitHub Issue mode**: Push -> **rewrite the Issue body as the implementation Issue** -> report summary (including Issue URL)
   - Replace the placeholder body of the Issue created in Phase 1 with the implementation Issue contents, following `templates/impl-issue.md`
   - Include: 概要 (overview), spec file links to consult during implementation, 受け入れ条件 (acceptance criteria), base branch
   - Acceptance criteria must be extracted from the spec docs as concrete completion conditions (avoid vague "implement it")
   - Write the new body to a temp file and apply with `gh issue edit <number> --body-file <temp-file>`, then delete the temp file
   - Keep the Issue open (do not close). It can be passed directly to `/impl #<number>`
4. **Local mode**: Report summary (file path list)

## Rules

- Never guess unknowns; always confirm with user
- **Always use `AskUserQuestion` with options for questions.** Never ask via text alone
- Max 4 questions per round
- Include reference ideas in each option's `description`
- When appending to existing specs, prioritize reuse/modification of existing features
- Always add revision history when updating documents
- Track progress with TaskCreate/TaskUpdate
- **If an existing spec directory is found, use those paths — not the defaults (`docs/`). Never create new subdirectories when existing ones already serve the same purpose**
- **When updating existing files, use Edit to modify them in place. Never create duplicate files in a different location**
