---
name: impl-wt-r-en
description: Run impl-wt then refine-git in an isolated worktree, from implementation through polishing and CI-green merge.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# impl-wt-r-en

A superset of `impl-wt`. Immediately after the worktree-isolated `/impl-wt-en` completes, run `/refine-git` to polish the PR until "critical/major=0 ∧ minor≤threshold", then wait for CI green and merge directly. A composite skill that also works well with parallel sweeps.

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI authenticated

## Arguments

Accepts arguments for both impl-wt and refine-git.

- **impl-wt side** (implementation target, pick one):
  - `/impl-wt-r-en #<Issue number>`: Fetch requirements from GitHub Issue
  - `/impl-wt-r-en <Issue URL>`: Fetch requirements from Issue URL
  - `/impl-wt-r-en <text>`: Use text as requirements
  - `/impl-wt-r-en` (no arguments): Interview the user
- **refine-git side** (polishing behavior, optional):
  - `--max-minor <N>`: Upper bound for minor findings (default 5)
  - `--max-iter <N>`: Review loop iteration cap (default 10)
  - `--no-merge`: Polish only, do not merge (default is direct merge after CI green)

## Phase 1: Argument separation

1. Extract refine-git flags (`--max-minor` / `--max-iter` / `--no-merge`) into `REFINE_ARGS`
2. Treat the rest as `IMPLWT_ARGS` to pass to impl-wt
3. State the separation result to the user in one line (e.g. `impl-wt args: #123 / refine-git args: --max-minor 3`)

## Phase 2: Implementation (run impl-wt)

1. Launch `impl-wt-en` with `IMPLWT_ARGS` via the Skill tool
2. Let it complete the full flow (worktree creation, requirement analysis, scope splitting, implementation cycle, PR creation)
3. Take the **PR number** and **worktree path** from the final report and hold them in `PR_NUMBER` / `WORKTREE_PATH`
4. If no PR was created, stop here and do not proceed to refine-git

## Phase 3: Polishing (run refine-git, reusing the worktree)

1. `cd <WORKTREE_PATH>` so that refine-git satisfies its existing-worktree reuse condition
2. Launch `refine-git` with `#<PR_NUMBER> <REFINE_ARGS>` via the Skill tool
3. refine-git detects "already launched inside a worktree" in its Phase 1 and reuses the worktree created by impl-wt (does not create a new one)
4. Unless `--no-merge` is given, refine-git waits for CI green and runs `gh pr merge --merge --delete-branch` + Issue close

## Phase 4: Final report

Merge the impl-wt PR information, worktree path, and removal command (`git worktree remove <path>`) with the refine-git JSON report (`status` / `iter` / remaining counts / `merged` / `report_path`) and report to the user in a single message.

## Prohibited actions

- Proceeding to refine-git when impl-wt failed or aborted before PR creation
- Launching refine-git **outside the worktree created by impl-wt** (a second worktree gets created; always `cd` first in Phase 3)
- Relaxing the prohibited actions of impl-wt / refine-git just because they were invoked through this composite skill
- Running impl-wt and refine-git in parallel (order matters)
- Skipping argument separation and passing everything to impl-wt (`--max-*` / `--no-merge` are unknown to impl-wt, so always extract them)
- **Launching `refine` instead of `refine-git`** (`refine` targets the whole repository; it picks up pre-existing findings unrelated to the PR and never converges)

## Rules

- All prohibited actions and rules of impl-wt and refine-git apply to this skill as well
- refine-git polishes **only the diff of the PR created by impl-wt** (use `/refine-sweep` separately if whole-codebase polishing is needed)
- Do not introduce any state management beyond argument parsing and PR number / worktree path handoff
- refine-git's state file `.sweep/state.json` stays inside the worktree (never pollute the main working tree)
- Always pass the PR number obtained in Phase 2 explicitly to refine-git in Phase 3 (prevents refine-git from guessing the current branch and grabbing the wrong PR)
- `refine-git` has no `-en` variant; invoke the Japanese skill directly and keep interacting with the user in 日本語
