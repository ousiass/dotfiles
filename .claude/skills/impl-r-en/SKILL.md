---
name: impl-r-en
description: Run impl then refine-git end-to-end, from implementation through polishing and CI-green merge.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# impl-r-en

A superset of `impl`. Immediately after `/impl-en` completes, run `/refine-git` to polish the PR until "critical/major=0 ∧ minor≤threshold", then wait for CI green and merge directly. A composite skill that removes the effort of manually invoking `/impl-en` → `/refine-git`.

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI authenticated

## Arguments

Accepts arguments for both impl and refine-git.

- **impl side** (implementation target, pick one):
  - `/impl-r-en #<Issue number>`: Fetch requirements from GitHub Issue
  - `/impl-r-en <Issue URL>`: Fetch requirements from Issue URL
  - `/impl-r-en <text>`: Use text as requirements
  - `/impl-r-en` (no arguments): Interview the user
- **refine-git side** (polishing behavior, optional):
  - `--max-minor <N>`: Upper bound for minor findings (default 5)
  - `--max-iter <N>`: Review loop iteration cap (default 10)
  - `--no-merge`: Polish only, do not merge (default is direct merge after CI green)

## Phase 1: Argument separation

1. Extract refine-git flags (`--max-minor` / `--max-iter` / `--no-merge`) into `REFINE_ARGS`
2. Treat the rest as `IMPL_ARGS` to pass to impl (Issue number / URL / text / empty)
3. State the separation result to the user in one line (e.g. `impl args: #123 / refine-git args: --max-minor 3`)

## Phase 2: Implementation (run impl)

1. Launch `impl-en` with `IMPL_ARGS` via the Skill tool
2. Let it complete the full flow (requirement analysis, scope splitting, implementation cycle, PR creation)
3. Take the **PR number** from the final report and hold it in `PR_NUMBER`
4. If no PR was created (impl aborted, etc.), stop here and do not proceed to refine-git

## Phase 3: Polishing (run refine-git)

1. Launch `refine-git` with `#<PR_NUMBER> <REFINE_ARGS>` via the Skill tool
2. refine-git creates its own worktree for the PR branch and runs review → fix → re-review
3. Unless `--no-merge` is given, refine-git waits for CI green and runs `gh pr merge --merge --delete-branch` + Issue close

## Phase 4: Final report

Merge the impl PR information with the refine-git JSON report (`status` / `iter` / remaining counts / `merged` / `report_path`) and report to the user in a single message.

## Prohibited actions

- Proceeding to refine-git when impl failed or aborted before PR creation (no PR exists, so always skip)
- Relaxing the prohibited actions of impl / refine-git just because they were invoked through this composite skill
- Running impl and refine-git in parallel (refine-git targets impl's PR, so the order matters)
- Skipping argument separation and passing everything to impl (`--max-*` / `--no-merge` are unknown to impl, so always extract them)
- **Launching `refine` instead of `refine-git`** (`refine` targets the whole repository; it picks up pre-existing findings unrelated to the PR and never converges)

## Rules

- All prohibited actions and rules of impl and refine-git apply to this skill as well
- refine-git polishes **only the diff of the PR created by impl** (use `/refine-sweep` separately if whole-codebase polishing is needed)
- Do not introduce any state management beyond argument parsing and PR number handoff (`.sweep/state.json` is managed by refine-git)
- Always pass the PR number obtained in Phase 2 explicitly to refine-git in Phase 3 (prevents refine-git from guessing the current branch and grabbing the wrong PR)
- `refine-git` has no `-en` variant; invoke the Japanese skill directly and keep interacting with the user in 日本語
