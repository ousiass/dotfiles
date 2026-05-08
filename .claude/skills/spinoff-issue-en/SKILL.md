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

- **Text**: Summary of the work to spin off (e.g., `/spinoff-issue-en login screen has no retry handler`)
- **Parent issue number / URL** (`--parent`): The original issue of the current work (e.g., `--parent #42`). **Required when called from another skill (e.g., `impl-en`).** The caller must pass the parent Issue number recorded in its Phase 1 via `--parent`.
- **No arguments**: Allowed only in standalone contexts without a parent Issue. Claude extracts a candidate summary from the recent work context.

When invoked from `impl-en` etc. with no arguments, Claude assembles the summary, classification, and parent links from the latest review findings, in-progress observations, or unresolved TODOs. Do **not** interview the user (the policy is post-hoc reporting). **If a parent Issue exists in the caller's context but `--parent` was not passed, Claude must reconstruct the parent Issue number from context before creating the issue.**

## Auto-creation guards (mandatory)

Because issues are created without user confirmation, follow these strictly. **Abort and confirm with the user** if any guard fires.

1. **Duplicate check**: Run `gh issue list --state open --search "<summary>"`. If a similar title/body exists, abort and ask via `AskUserQuestion` whether to comment on the existing one or create a new one.
2. **Volume guard**: If creating 4+ consecutive issues from one calling skill in a single session, abort and confirm.
3. **Scope self-check**: Ask once: "Does this actually belong to the current scope?" If the boundary is unclear, abort and confirm.
4. **Empty-content guard**: If the title/body lacks concrete facts (file path, function name, repro condition), abort, re-investigate the code yourself, and only then create.

## Phase 1: Context extraction and classification

1. Determine the summary (start from arguments; otherwise extract from recent findings)
2. Confirm related code with `Grep` / `Read` and identify file paths and function names (counters the empty-content guard)
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

When multiple are created, report as a list. Then return to the calling skill (e.g., `impl-en`) and continue the current scope.

## Rules

- **Do not ask the user** by default. Only ask via `AskUserQuestion` when an auto-creation guard fires.
- Cap at **3 consecutive creations** per session; ask before more.
- Title and labels align with `bug-report-en` and the CLAUDE.md commit convention.
- The only edit allowed on the parent Issue / PR body is appending the spinoff section.
- Do not modify code. The deliverable is the Issue only.
- Keep the report format fixed so the calling skill can parse the result mechanically.
