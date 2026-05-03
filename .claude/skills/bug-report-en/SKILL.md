---
name: bug-report-en
description: Interactively gather bug details, investigate code, and create a structured GitHub Issue.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# bug-report-en

Usable by non-engineers. Just answer questions to create a proper bug report.

## Prerequisites

- Claude Code environment
- `gh` CLI (for GitHub Issue output)

## Arguments

- **Text** (e.g., `/bug-report-en Can't log in`): Use as initial info, interview for missing details
- **No arguments**: Start interviewing from scratch

## Phase 1: Interview

**Ask in plain language without technical jargon.**

#### 1-1: Basic Information

Use `AskUserQuestion` to gather (skip what's already known from arguments):
1. **What happened**: What problem occurred
2. **Where it happened**: Which screen, feature, or page
3. **Error messages**: Displayed on screen or console (request screenshots)

#### 1-2: Follow-up Questions

Ask **only what's needed** based on responses (max 3, don't ask what can be inferred):

| Situation | What to ask |
|-----------|-------------|
| Error message exists | Error details, screenshots |
| Reproduction unclear | Every time or specific conditions |
| Screen/UI issue | Browser, device, screen size |
| Data issue | Specific data/account only |
| Timing issue | Since when, recent changes |
| Steps unclear | Specific operation steps |

## Phase 2: Codebase Investigation

1. **Identify related code** — Search by screen/feature name/error message with `Grep`/`Glob`. Use `Explore` agent for broader investigation if needed
2. **Estimate cause** — Trace from error messages/stack traces. State confidence level (certain / likely / needs investigation)
3. **Check impact scope** — Check other features using same code, related tests
4. **Attempt reproduction** — Only if reproducible via tests or commands. Do not create tests

## Phase 3: Duplicate Check

1. Search existing Issues with `gh issue list --state open --search "<bug-summary>"`
2. If similar Issue found -> report to user, confirm whether to comment on existing or create new

## Phase 4: Preview and Output Destination

1. Create draft from gathered info and investigation results
2. Show preview to user (technical content + plain explanation)
3. Apply revisions if any
4. Confirm output destination with `AskUserQuestion`:
   - **GitHub Issue** (recommended)
   - **Local MD file**

## Phase 5: Output

#### GitHub Issue
- Create with `gh issue create`, title `bug: <summary>`, label `bug`
- Use template from `templates/issue.md`
- Report URL to user

#### Local MD
- Generate `bug-report-<summary-kebab-case>.md`
- Report path to user

## Severity Criteria

| Severity | Criteria | Example |
|----------|----------|---------|
| Critical | Service down, data loss, security risk | Can't log in, data deleted |
| High | Major feature unusable, no workaround | Search broken, can't save |
| Medium | Feature works but inconvenient, workaround exists | Display broken, slow |
| Low | Minor, no usage impact | Typo, color mismatch |

## Rules

- **No technical jargon** in interviews. Mirror user's own terms only
- **Minimal questions**. Don't ask what can be inferred
- Code investigation must **verify against actual code**, not guess
- State confidence level honestly for cause estimates
- **Always preview and get user approval** before creating Issue
- Do not modify code. Output is Issue only
- If fix is needed, suggest `/bug-fix #<issue-number>`
