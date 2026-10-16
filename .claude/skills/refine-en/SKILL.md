---
name: refine-en
description: Loop review→fix→re-review over the whole repository, then wait for CI green, merge directly, and close the Issue.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

**Source of truth: the Japanese `refine` is canonical; this `-en` is a translation and MUST be updated after it (applies to `refine-en/references/*.md` too).**

# refine-en

Loop review → fix → re-review until the **whole repository** is down to "minor findings only" under the review criteria. Fixes are stacked directly on one PR branch.

**To polish only a PR's diff, use `refine-git-en`.** Polishing PRs created by `impl` / `impl-wt` / `issue-sweep` is entirely `refine-git-en`'s job. Using this skill on a feature PR bloats the scope and ends at `max_iter` without ever reaching the threshold.

| Skill | Target | How fixes flow | Main use |
|---|---|---|---|
| `refine-git-en` | PR diff only | Fix directly on the PR branch | Polishing feature PRs (default) |
| **refine-en** (this skill) | Whole repository | Fix directly on the PR branch (one PR) | Bulk cleanup of small/medium repositories |
| `refine-sweep-en` | Whole repository | File Issues → work through them with `impl-wt-en` (multiple PRs) | Continuous quality improvement of large repositories |

## Arguments

- `/refine-en` — Target the current branch / PR
- `/refine-en #<PR number>` — Target a specific PR
- `/refine-en --max-minor <N>` — Upper limit for minor findings (default 5)
- `/refine-en --max-iter <N>` — Upper limit on review-loop iterations (default 10)
- `/refine-en --no-merge` — Polish only, do not merge (default: wait for CI green and merge directly)

## Prerequisites

- `git`, `gh` CLI authenticated
- Target PR / branch can be checked out
- Write permission to the `.sweep/` directory (for telemetry)

## Phase 1: Setup and Review Skill Selection

Set `skill_name="refine"` / `scope_label="リポジトリ全体"` and run steps 1–7 of `references/common-setup.md` (target identification, worktree acquisition, variable initialization, state.json initialization, HALT / Atomic Design detection, frontend guard).

For the state-management spec, see `references/state-and-telemetry.md`.

### 1-8. Decide the review skill list (all whole-repo scan variants)

- Always: `code-review-en`, `doc-drift-en`, `spec-audit-en`
- Only when `HAS_HALT=true`: add `halt-review-en`
- Only when `HAS_ATOMIC=true`: add `atomic-review`

## Phase 2: Review → Fix Loop

Each iteration launches one parallel subagent per review skill. Launch per `harness-model` (`subagent_type: review`; do not use `claude`; on Cursor do not pass `model`). **The main thread never touches code.**

### 2-1. Aggregate reviews (parallel)

Launch the chosen skills **in parallel within the same message**. Each agent runs exactly one specialist skill and returns findings as JSON.

```
Agent({
  description: "refine iter <iter+1> — code-review",
  subagent_type: "review",
  prompt: """
Run /code-review-en on the whole repository via the Skill tool.
If asked for the output destination, choose "Console output" and do not create Issues.

Classify the findings by the severities below and return them as a single JSON line in the final message:
- critical: bugs, security problems, data corruption, test failures
- major: serious design flaws, performance degradation, public API inconsistencies
- minor: naming, comments, minor readability, style

{"source": "code-review", "critical": [{"file":"...", "line": N, "msg":"..."}], "major": [...], "minor": [...]}
"""
})

Agent({
  description: "refine iter <iter+1> — doc-drift",
  ... same as above, run /doc-drift-en, return "source": "doc-drift"
})

Agent({
  description: "refine iter <iter+1> — spec-audit",
  ... same as above, run /spec-audit-en, return "source": "spec-audit"
  # spec-audit normally creates Issues. When called from refine,
  # state explicitly in the prompt: "Do not create Issues; return only the findings JSON"
})

# Only when HAS_HALT=true
Agent({
  description: "refine iter <iter+1> — halt-review",
  ... same as above, run /halt-review-en, return "source": "halt-review"
})

# Only when HAS_ATOMIC=true
Agent({
  description: "refine iter <iter+1> — atomic-review",
  ... same as above, run /atomic-review, return "source": "atomic-review"
})
```

Aggregate each agent's returned JSON:

```bash
findings=$(printf '%s\n' "$resp_code" "$resp_doc" "$resp_spec" "$resp_halt" "$resp_atomic" | \
  jq -s '{
    critical: map(.critical // []) | flatten,
    major:    map(.major // [])    | flatten,
    minor:    map(.minor // [])    | flatten,
    by_source: map({(.source): {c:(.critical|length), m:(.major|length), mn:(.minor|length)}}) | add
  }')
```

### 2-2. Append telemetry + update state.json

Run "Per-iteration telemetry append + state.json update" in `references/state-and-telemetry.md` (`source` becomes `refine`).

### 2-3. Threshold decision

```
if critical == 0 && major == 0 && minor <= max_minor:
  → success, go to Phase 3
if iter >= max_iter:
  → status=iter_limit, go to Phase 3 (finish with findings remaining)
if (critical + major) has not dropped below the previous value for 2 consecutive iterations:
  → status=no_progress, go to Phase 3
otherwise:
  → go to 2-4
```

**no_progress decision**: the previous value is in `last_counts` of state.json. If this iteration's `critical + major` is equal to or greater than the previous one, count one "stall"; **abort after 2 consecutive stalls** (not after 1, because fixes can temporarily add findings as a side effect). If it dropped, reset the stall count to 0. The Phase 3 report MUST include `status: no_progress` and the findings remaining at the point of stall. Pick the status name from the enum in `references/merge-and-report.md`; never invent strings outside the enum (e.g. `stuck`).

**Rule of thumb for aborting**: a whole-repo scan tends to produce a large first-iteration count. Once it is clear the scale does not fit in one PR (e.g. more than 30 critical + major), you may suggest to the user switching to `refine-sweep-en`.

### 2-4. Fix agent

**Before** launching the agent, record `prev_head=$(git rev-parse HEAD)` in the main thread (used in 2-5 to get "the files touched by this fix").

```
Agent({
  description: "refine iteration <iter+1> fix",
  subagent_type: "develop",
  prompt: """
Fix the following findings on PR #<n> (branch: <branch>):

CRITICAL:
<list critical findings as file:line:msg>

MAJOR:
<list major findings>

MINOR (there are <minor - max_minor> excess minor findings; fix at least <minor - max_minor> of them, highest priority first):
<list minor findings>

Steps:
1. Switch with `git checkout <branch>`
2. Fix the findings in order (this agent itself is the develop agent)
3. Add tests where needed (regression tests are mandatory)
4. Push the fix commit with `git push`
5. Final message JSON: {"fixed_critical": N, "fixed_major": N, "fixed_minor": N, "commit": "<sha>"}
   or on failure: {"failure": "<reason>"}
"""
})
```

On failure, abort the loop and go to Phase 3 with `status=agent_failed`.

### 2-5. Next iteration

**From the second iteration on, narrow the review scope.** Re-scanning the whole repository every time is wasteful (most of the code seen in iteration 1 was not changed by the fixes):

```bash
# review scope = files touched by the previous fix ∪ files with unresolved findings
touched=$(git diff --name-only "$prev_head"...HEAD)   # prev_head is the value recorded before the 2-4 fix push
unresolved=$(echo "$findings" | jq -r '(.critical + .major + .minor)[].file // empty')
review_scope=$(printf '%s\n%s\n' "$touched" "$unresolved" | sort -u | grep -v '^$')
```

In the next iteration, pass each review agent `review_scope` instead of "the whole repository". **A whole-repo scan is needed only in iteration 1.**

Do `iter+=1` and return to Phase 2-1.

## Phase 3: Merge → Report Generation and Termination

Run steps 1–8 of `references/merge-and-report.md`.

## Forbidden Actions

- **The main thread itself modifies code** (the CTO does not touch implementation — same principle as impl-wt and issue-sweep)
- Mixing the review agent and the fix agent in the same call (keep them independent)
- Ending the loop with "good enough" before the threshold is reached (the only allowed stops are reaching `max_iter` and the 2-3 no_progress decision)
- Looping infinitely past `max_iter`
- **Ignoring a stall (critical+major not dropping for 2 consecutive iterations) and running to `max_iter`** (cycling unfixable findings accounts for most of the elapsed time; hand back to a human early)
- **Re-scanning the whole repository from the second iteration on** (narrow to `review_scope` in 2-5; the whole-repo scan is for iteration 1 only)
- Introducing side-effect bugs while fixing minors (if the post-fix review reports critical, continue iterating)
- **Using this skill on a feature PR** (it picks up pre-existing problems outside the diff and bloats the scope; use `refine-git-en`)
- **Skipping any of the mandatory reviews (code-review / doc-drift / spec-audit)** (the verdict integrates all perspectives)
- **Skipping halt-review on a HALT project** (always launch in parallel when HAS_HALT=true)
- **Skipping atomic-review on an Atomic Design project** (always launch in parallel when HAS_ATOMIC=true; exclusivity with HAS_HALT=true is guaranteed by the detection side)
- **Continuing on a frontend project that has not adopted Atomic Design** (always abort at the Phase 1 IS_FRONTEND guard)
- **When merging, declaring `clean` by estimation without re-running the final review** (with `--no-merge`, use the final iteration's result as-is)
- **Overwriting `.sweep/state.json` owned by the calling sweep / setting `phase=terminal`** (see the guard in step 4 of `references/common-setup.md`)
- **Skipping the merge although status=clean** (except when `--no-merge` is explicit)
- **Using `gh pr merge --auto`** (behavior depends on the repository's `allow_auto_merge` setting and stops with a GraphQL error when OFF; standardized on polling for CI green and then merging directly)
- Skipping the merge-completion check and moving on to report generation
- **Checking out in the main worktree to switch to the PR branch** (breaks worktree isolation and pollutes the main tree)
