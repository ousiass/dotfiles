---
name: design-review-en
description: Review UI component design quality and generate Issue or report.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# design-review-en

## Prerequisites

- Claude Code environment
- `gh` CLI (for GitHub Issue output)

## Arguments

- No arguments: Confirm review target files/directories with `AskUserQuestion`
- Path specified: Check only the specified files or directories

## Phase 1: Project Structure and Design Foundation

1. Identify directory structure and framework (React / Vue / Svelte, etc.) of target files
2. Detect project design foundation files:
   - CSS framework config (`tailwind.config.*`, `uno.config.*`, etc.)
   - Design tokens / theme definitions (`theme.ts`, `tokens.*`, `variables.css`, etc.)
   - Global styles (`global.css`, `base.css`, etc.)
   - Existing UI component libraries (shadcn, Vuetify, MUI, etc.)
3. Read detected design foundation as review criteria
4. List target files and create tasks with TaskCreate

## Phase 2: Design Quality Check

Check all target files. Split by directory if there are many files.

Check criteria details in `references/check-criteria.md`.

Main categories:
- **Visual consistency**: Token compliance for colors, typography, spacing, border-radius, shadows
- **Layout & responsive**: Breakpoints, containers, overflow
- **Accessibility**: Contrast ratio, focus, ARIA, keyboard navigation
- **Interaction**: hover/focus/active states, loading/error/empty states
- **Component API**: Props design, variants, composition patterns
- **Design token compliance**: Hardcoded value detection, theme variable usage

## Phase 3: Report Generation

1. Confirm output destination with `AskUserQuestion`:
   - **GitHub Issue** (recommended): Title `design-review: Design quality report (<branch>, <YYYY-MM-DD>)`
   - **Local MD file**: `design-review-report.md`
2. Use report format from `templates/report.md`
3. Report summary to user

## Severity Criteria

| Severity | Criteria |
|----------|----------|
| Critical | Accessibility violation (WCAG A non-compliant), inoperable UI, major display breakage |
| Important | Design system inconsistency, responsive breakage, missing states (loading/error) |
| Suggestion | Visual improvements, interaction enhancement, tokenization recommendations |
| Minor | Style fine-tuning, naming improvements, code cleanup |

## Rules

- Never report based on guesses. Verify against actual code
- Respect project design foundation (tokens, theme settings)
- If no design foundation detected, use general UI/UX best practices
- Always include file path and line number in findings
- Include concrete code examples in improvement suggestions
- Always include Critical/Important findings. Include Suggestion/Minor only if clear benefit
- Respect framework conventions and existing code style
- Track progress with TaskCreate/TaskUpdate
