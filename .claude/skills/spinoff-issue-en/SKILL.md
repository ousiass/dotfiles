---
name: spinoff-issue-en
description: Spin off out-of-scope work discovered during implementation as a separate GitHub Issue.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# spinoff-issue-en

Used when Claude — typically while running `impl-en`, `impl-wt-en`, `bug-fix-en`, or similar skills — judges that a discovered piece of work belongs in a separate issue. **Created without user confirmation; the URL is reported afterwards.** The guards under "Auto-creation guards" must be observed to prevent runaway issue creation.

## Prerequisites

- Claude Code environment
- `gh` CLI (authenticated)

## When to invoke (from other skills)

Invoke when the discovered work would **bloat the current PR or is independent of the current requirements**.

- Out-of-scope additions or improvements (feat / chore)
- Bugs unrelated to the current scope (bug)
- Refactor proposals that would balloon the current PR (refactor)
- Spec/document inconsistencies or missing items (docs / spec)

Do NOT invoke for:

- Work that belongs in the current scope (do it in the current PR)
- Restating "leave as TODO" or "do later" — those are forbidden by the calling skill, not a spinoff target
- One-off typos or minor questions (fix directly or ignore)

## Arguments

Pass any combination as Claude finds convenient:

- **Batch input** (`--batch <path>`): JSONL written by `impl-en` / `impl-wt-en` (one line = `{parent, type, title, files, why}`). **Use this form when called from another skill.** All entries are handled in a single invocation, with gh queries batched (Phase 0).
- **Text**: Summary of the work to spin off (e.g., `/spinoff-issue-en login screen has no retry handler`)
- **Parent issue number / URL** (`--parent`): The original issue of the current work (e.g., `--parent #42`). Always pass it for text-driven runs that have a parent.
- **No arguments**: Allowed only in standalone contexts without a parent Issue. Claude extracts a candidate summary from the recent work context.

When invoked from `impl-en` etc. with no arguments, Claude assembles the summary, classification, and parent links from the latest review findings, in-progress observations, or unresolved TODOs. Do **not** interview the user (the policy is post-hoc reporting). **If a parent Issue exists in the caller's context but `--parent` was not passed, Claude must reconstruct the parent Issue number from context before creating the issue.**

## Auto-creation guards (mandatory)

Because issues are created without user confirmation, follow these strictly. Guards 1 and 2 **skip that single entry and report it in Phase 5** (no user confirmation). Guards 3 and 4 **abort and confirm with the user**.

1. **Duplicate check**: Match against the existing-issue list fetched in Phase 0 (for non-`--batch` runs, `gh issue list --state open --search "<summary>"`). If a similar title/body exists, **skip that single entry** and list it in the Phase 5 report as "not filed — duplicate" (do not abort the whole batch).
2. **Volume guard**: At most **5 issues per invocation**. List every excess entry in the Phase 5 report as "not filed — over cap" instead of creating it. Keep the counter in `.sweep/spinoff-count` so it **accumulates across subagents** (an in-context count resets per agent and does not work):

   ```bash
   mkdir -p .sweep; [ -f .sweep/spinoff-count ] || echo 0 > .sweep/spinoff-count
   created=$(cat .sweep/spinoff-count)   # increment and write back after each creation
   ```
3. **Scope self-check**: Ask once: "Does this actually belong to the current scope?" If the boundary is unclear, abort and confirm.
4. **Empty-content guard**: If the title/body lacks concrete facts (file path, function name, repro condition), abort, re-investigate the code yourself, and only then create.

## Phase 0: Input normalization and batched gh queries (`--batch` only)

Load the draft and **run each gh query exactly once here** rather than repeating it per entry:

```bash
drafts=$(jq -sc '.' "<batch path>")                                           # all entries as an array
existing=$(gh issue list --state open --json number,title,labels --limit 300) # for the duplicate check
labels=$(gh label list --limit 200 --json name -q '.[].name')                 # for the label existence check
```

Then loop Phases 1–3 over the draft entries. Never re-run `gh issue list --search` / `gh label list` per entry.

## Phase 1: Context extraction and classification

1. Determine the summary (start from arguments; otherwise extract from recent findings)
2. Confirm related code with `Grep` / `Read` and identify file paths and function names (counters the empty-content guard). **Under `--batch`, skip re-investigation when the draft's `files` / `why` are already concrete** (the caller recorded them at discovery time)
3. Classify (pick the primary one if multiple apply):

   | Kind | Use | type label |
   |------|-----|-----------|
   | bug | Defect | `type:bug` |
   | feat | New feature / improvement | `type:feat` |
   | chore | Tooling / setup | `type:chore` |
   | refactor | Design change / tech debt | `type:refactor` |
   | docs | Doc fix / spec mismatch | `type:docs` |

4. Identify the parent Issue / source PR (if running inside `impl-en`, use `gh pr view --json url,number`, or find the Issue linked to the current branch)

## Phase 2: Title, labels, and body

### Title format

`<type>: <summary>` (aligned with the commit convention in CLAUDE.md). 日本語 also acceptable.

Examples:
- `feat: add retry button on login screen`
- `bug: order summary screen shows duplicated total`
- `refactor: extract AuthMiddleware into Strategy pattern`
- `docs: API spec auth-error table is outdated`

### Labels (always attach 4 or 5)

1. **`spinoff`** (fixed) — marker for issues created by this skill
2. **`type:<kind>`** — per Phase 1
3. **`area:<area>`** — kebab-case lowercase ASCII; module/directory name confirmed from code (e.g., `area:auth`, `area:checkout`)
4. **`severity:<level>`** (when bug) or **`priority:<level>`** (otherwise)
   - severity for bug uses the same scale as `bug-report-en` (critical/high/medium/low)
   - priority: `priority:high` / `priority:medium` / `priority:low`
5. **`bug`** (only when `type:bug`) — added so the issue is discoverable via the same `label:bug` query used by `bug-report-en`

### Label existence check (always run before creation)

Under `--batch`, reuse `$labels` from Phase 0. Fetch here only for standalone runs:

```bash
gh label list --limit 200 --json name -q '.[].name'
```

`spinoff` may be auto-created if missing (`gh label create spinoff --color BFD4F2 --description "Spun off from another issue/PR"`). Any other missing label aborts creation; ask the user before creating.

### Body

Use `templates/issue.md`. Fill at minimum:

- **Background**: Why this is a separate issue (link to source work / PR / Issue, and the reason for not bundling)
- **What to do**: 1–3 lines, concrete
- **Affected code**: File paths (preferably with line numbers, e.g., `src/auth/middleware.ts:42`)
- **Acceptance criteria**: Bulleted completion list (feat/refactor) / repro + expected behavior (bug)
- **Parent issue / source PR**: `Related: #<num>` if any

## Phase 3: Issue creation

```bash
gh issue create \
  --title "<type>: <summary>" \
  --label spinoff \
  --label "type:<kind>" \
  --label "area:<area>" \
  --label "severity:<level>" `# when bug` \
  --label bug              `# only when type:bug` \
  --body-file <tmpfile>
# For non-bug issues, replace --label "severity:<level>" with --label "priority:<level>"
# Do not add --label bug for non-bug issues
```

Capture the URL on success.

## Phase 4: Link to parent Issue / source PR

Run only if applicable.

1. **Parent Issue**: Append `- [ ] #<new> <title>` under a `## Spinoff issues` section at the end of the parent issue body
   - Add to existing section if present; otherwise create one
   - `gh issue view <parent> --json body -q .body` → tmpfile → edit → `gh issue edit <parent> --body-file <tmp>` → delete tmp
   - **Under `--batch`, do this once per parent** (collect all children of the same parent, then run a single read-modify-write; never re-edit the parent per child)
2. **Source PR**: Append `Related spinoff: #<new>` to the PR body via `gh pr edit`
3. **From the new Issue**: Always include `Source: #<parent> / PR: #<pr>` in the body (covered by Phase 2 template)

## Phase 5: Post-hoc report

Report once. Do not ask for confirmation (already created):

```
Created spinoff issue:
- #<num> <title>
- URL: <issue URL>
- Labels: spinoff, type:<kind>, area:<area>, ...
- Parent: #<parent> (linked) / PR: #<pr> (linked)
```

When multiple are created, report as a list. **Entries skipped as duplicates or over the cap must always be listed with their reason** (never dropped silently):

```
Not filed (2 duplicates / 3 over cap):
- <title> — duplicate of #<num>
- <title> — over the 5-per-invocation cap
```

Then return to the calling skill (e.g., `impl-en`) and continue the current scope.

## Rules

- **Do not ask the user** by default. Only ask via `AskUserQuestion` when an auto-creation guard fires.
- The creation cap follows auto-creation guard 2 (5 in total, tracked in `.sweep/spinoff-count`). Excess entries are **reported as not filed without asking the user** (listing them is cheaper than blocking on a confirmation).
- Title and labels align with `bug-report-en` and the CLAUDE.md commit convention.
- The only edit allowed on the parent Issue / PR body is appending the spinoff section.
- Do not modify code. The deliverable is the Issue only.
- Keep the report format fixed so the calling skill can parse the result mechanically.
