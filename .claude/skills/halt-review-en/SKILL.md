---
name: halt-review-en
description: HALT architecture compliance review (routing, Templ/HTMX, Atomic Design, Lit, security, build)
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# halt-review-en

Review projects built with the HALT architecture (HTMX + Atomic Design + Lit + Templ + Huma) from HALT-specific perspectives.

## Prerequisites

- Claude Code environment
- `gh` CLI (for GitHub Issue output)
- Target project uses HALT architecture

## Arguments

- No arguments: Check the entire project in the current directory
- Path specified: Check only the specified directory or file

## Phase 1: Project Structure Analysis

1. Identify directory structure and locate each HALT layer:
   - Go sources (`internal/`, `cmd/`)
   - Templ templates (`web/` with `atoms/`, `molecules/`, `organisms/`, `pages/`, `layout/`)
   - Lit components (`static/src/components/` or similar)
   - Route definitions (`router/` or `handler/`)
   - Build config (`esbuild.config.*`, `package.json`)
2. Detect app prefix from Web Component `@customElement` definitions
3. List target files and create tasks with TaskCreate for each check category

## Phase 2: HALT Review

Run all check categories sequentially. **Check all target files.** Split by directory if there are many files.

Check category details in:
- Routing consistency: `references/check-routing.md`
- Templ ↔ HTMX connection: `references/check-templ-htmx.md`
- Cross-layer consistency: `references/check-cross-layer.md`
- HATEOAS compliance: `references/check-hateoas.md`
- Atomic Design structure: `references/check-atomic.md`
- Lit Web Components: `references/check-lit.md`
- Go layered architecture: `references/check-backend-layer.md`
- Security: `references/check-security.md`
- Build configuration: `references/check-build.md`

## Phase 3: Report Generation

1. Confirm output destination with `AskUserQuestion`:
   - **GitHub Issue** (recommended): Title `halt-review: HALT architecture review (<branch>, <YYYY-MM-DD>)`
   - **Local MD file**: `halt-review-report.md`
   - **Console output**: Print the report directly in the conversation
2. Use report format from `templates/report.md`
3. Report summary to user

## Severity Criteria

| Severity | Criteria |
|----------|----------|
| Critical | Routing mismatch (HTMX request to nonexistent path), Templ↔Lit attribute binding mismatch, static asset path mismatch, security flaw (missing CSRF) |
| Important | HATEOAS violation (hidden/disabled action control, Lit URL hardcoding), HALT design violation (JSON response where HTML expected, unnecessary Web Component), Atomic Design/Go layer dependency inversion, missing Huma registration/I/O structs, stale Templ generation |
| Suggestion | Naming inconsistency, component placement optimization, hx-swap strategy improvement |
| Minor | Code organization, style unification, trivial naming improvement |

## Rules

- Never report based on guesses. Verify against actual code
- Always include file path and line number in findings
- Provide concrete improvement suggestions
- Always include Critical/Important findings. Include Suggestion/Minor only if clear benefit
- Respect project conventions and existing code style
- Track progress with TaskCreate/TaskUpdate
