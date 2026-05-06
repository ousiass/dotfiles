---
name: issue-split-en
description: Interactively split a GitHub Issue into scope-based sub-issues
user-invocable: true
---

# issue-split-en

Split a large Issue (e.g. spec Issue created by spec-gen) into implementable scope-based sub-issues.
Confirm each sub-issue with the user one by one before creation.

## Prerequisites

- Claude Code environment
- `gh` CLI (authenticated)

## Arguments

- **Issue number** (e.g. `/issue-split-en #123`): Target GitHub Issue to split
- **Issue URL** (e.g. `/issue-split-en https://github.com/owner/repo/issues/123`): Same
- **No arguments**: Ask user for Issue number

## Phase 1: Issue Retrieval and Analysis

1. Fetch the source Issue with `gh issue view <number> --json title,body,labels,url`
2. If the Issue body links to spec documents, read them with Read
   - Also search with Glob: `**/spec/**/*.md`, `**/specs/**/*.md`, `**/docs/**/*.md`
3. Understand the full scope of requirements, create a task with TaskCreate

## Phase 2: Scope Split Proposal

1. Split the Issue into **independently implementable scope units**
   - Typical split axes: environment setup, backend (API/DB), frontend, test/CI, etc.
   - Determine implementation order based on dependencies
2. Present the split proposal in `AskUserQuestion` using `preview`

   Preview format:
   ```
   1. <Title>  [depends: none]
      Summary: ...
   2. <Title>  [depends: #1]
      Summary: ...
   ```

3. Options:
   - **Approve this split** — proceed as is
   - **Split finer** — further divide specified scopes
   - **Merge scopes** — consolidate scopes
   - **Modify split** — free-text adjustments

4. Repeat until the user is satisfied

## Phase 3: Interactive Sub-issue Confirmation

**Repeat for each scope (in implementation order, one at a time):**

#### 3-1: Draft Sub-issue

Extract relevant information from the source Issue and specs:

- **Title**: `<type>: <scope implementation>` (ready for impl skill to pick up)
  - Choose type by scope nature: `feat` (feature), `chore` (env setup), `test` (test/CI), `docs` (documentation), etc.
- **Body**: Follow `templates/sub-issue.md` format
- **Labels**: Inherit from source Issue + add scope labels (e.g. `scope:backend`, `scope:frontend`) if available

##### Filling the "Related Specs" section

To prevent implementation drift, the `Related Specs` section must embed **only the spec content relevant to this sub-issue's scope**. Do not just link.

Extraction rules:
- Pick only the spec sections matching this scope (e.g. for backend: API spec / ER diagram / DB migration; for frontend: screen requirements / component design / UI flow)
- Cross-cutting specs that apply to all sub-issues (non-functional requirements, overall architecture diagram) should be referenced in the key points list only — do not quote the full content
- Do not include spec sections unrelated to this scope

How to fill:
1. **Key Points**: List `<spec file> › <section name>` with a one-line summary so the implementer can grasp at a glance what must be satisfied
2. **Full Section Excerpts**: Read the section and quote it **verbatim** (headings, body, tables, Mermaid diagrams, code blocks) wrapped in Markdown blockquotes (`>`)
3. **References**: Record the file path (with line numbers if possible, e.g. `docs/api.md:120-180`)

Notes:
- Do not summarize or rewrite the spec — quote the original (the goal is to prevent drift)
- Always include the source file path and section name so the original can be traced
- For scopes with no spec yet, write "No spec available. Decide during implementation."

#### 3-2: User Confirmation

Present draft via `AskUserQuestion` with preview:

- **Create as is**
- **Modify first** — describe changes, apply, re-confirm
- **Skip this scope**

## Phase 4: Sub-issue Creation and Linking

1. Create each approved sub-issue with `gh issue create`
   - Labels: `--label <label1> --label <label2>`
   - Record created issue numbers

2. Append sub-issue list to the parent Issue body:
   1. Fetch existing body with `gh issue view <number> --json body -q .body`
   2. Append "## Sub-issues" section (if already exists, keep existing links and add new ones)
      ```
      ## Sub-issues

      In implementation order:
      - [ ] #<number> <title>
      - [ ] #<number> <title>
      ```
   3. Write to temp file and update with `gh issue edit <number> --body-file <temp-file>`
   4. Remove temp file

3. Report summary to user:
   - Parent Issue URL
   - Each sub-issue URL with implementation order
   - Example usage with impl skill: `/impl #<first sub-issue number>`

## Rules

- Always use `AskUserQuestion` with options for questions. Never ask with plain text only
- Max 4 questions per round
- Include decision context in each option's `description`
- Sub-issue titles must be in a format that impl skill can directly work with
- Always get user approval before creating Issues
- Do not modify the source Issue content (only append sub-issue section)
- Track progress with TaskCreate/TaskUpdate
- **Each sub-issue body must embed the relevant spec content as "key points + full quoted sections" — never just a link.** Quote the original verbatim without summarizing or rewriting (to prevent implementation drift)
