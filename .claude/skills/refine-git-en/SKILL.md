---
name: refine-git-en
description: Loop review→fix→re-review over the diff against the git remote, then wait for CI green, merge directly, and close the Issue.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

**Source of truth: the Japanese `refine-git` is canonical; this `-en` is a translation and MUST be updated after it.**

# refine-git-en

The diff version of `refine-en`. Loop review → fix → re-review until **only the PR's diff** is down to "minor findings only" under the review criteria.

All uses for polishing PRs created by `impl` / `impl-wt` / `issue-sweep` belong here. Picking up pre-existing problems outside the diff means the threshold is never reached and files unrelated to the PR get modified.

| Skill | Target | How fixes flow |
|---|---|---|
| **refine-git-en** (this skill) | PR diff only | Fix directly on the PR branch |
| `refine-en` | Whole repository | Fix directly on the PR branch (one PR) |
| `refine-sweep-en` | Whole repository | File Issues → work through them with `impl-wt-en` (multiple PRs) |

## Arguments

- `/refine-git-en` — Target the current branch / PR
- `/refine-git-en #<PR number>` — Target a specific PR
- `/refine-git-en --max-minor <N>` — Upper limit for minor findings (default 5)
- `/refine-git-en --skip-minor` — Exclude minor findings from threshold decisions and fix targets (still detected and reported). Calls from `issue-sweep-en` always add this
- `/refine-git-en --max-iter <N>` — Upper limit on review-loop iterations (default 10)
- `/refine-git-en --no-merge` — Polish only, do not merge (default: wait for CI green and merge directly)
- `/refine-git-en --base-ref <ref>` — Explicitly specify the diff comparison target (e.g. `origin/sweep/issue-sweep-20260831-120000`). Takes precedence over the PR's baseRefName. **Calls from a sweep's single-pr mode always add this** — comparing against `origin/develop` instead of the integration branch pulls other batches' already-integrated diffs into the review and the scope grows without bound

## Prerequisites

- `git`, `gh` CLI authenticated
- Target PR / branch can be checked out
- Write permission to the `.sweep/` directory (for telemetry)

## Phase 1: Setup and Fix the Diff Scope

Set `skill_name="refine-git"` and run steps 1–7 of `references/common-setup.md` in `refine-en` (target identification, worktree acquisition, variable initialization, state.json initialization, HALT / Atomic Design detection, frontend guard).

For the state-management spec, see `references/state-and-telemetry.md` in `refine-en`.

### 1-8. Fix the diff scope (specific to this skill, mandatory)

Right after acquiring the worktree, always fix the comparison target and the changed-file list:

```bash
# Comparison target priority: --base-ref > PR's baseRefName > origin/develop > origin/main
git fetch origin
if [[ -n "${base_ref_opt:-}" ]]; then
  # Explicit specification never falls back (falling to origin/main when it does not exist would inflate the diff)
  base_ref="$base_ref_opt"
  git rev-parse --verify "$base_ref" >/dev/null 2>&1 \
    || { echo "ERROR: --base-ref $base_ref が存在しません"; exit 2; }
else
  base_ref="origin/${base_branch:-develop}"
  git rev-parse --verify "$base_ref" >/dev/null 2>&1 || base_ref="origin/main"
fi

merge_base=$(git merge-base "$base_ref" HEAD)
changed_files=$(git diff --name-only "$merge_base"...HEAD)

if [[ -z "$changed_files" ]]; then
  echo "ERROR: $base_ref との差分が空です。refine-git の対象がありません。"
  exit 2
fi

scope_label="\`${base_ref}...HEAD\` の差分のみ（$(printf '%s\n' "$changed_files" | wc -l) files）"
```

Reuse `base_ref` / `merge_base` across all iterations. Re-fetch `changed_files` **after every fix push**.

### 1-9. Decide the review skill list (all diff-scoped variants)

**Candidates (`source` names):**

- Always candidates: `code-review-git`, `doc-drift-git`, `spec-audit-git`
- Add as candidate only when `HAS_HALT=true`: `halt-review` (**pass the changed-file paths as arguments**)
- Add as candidate only when `HAS_ATOMIC=true`: `atomic-review` (**pass the changed-file paths as arguments**)

**Not every candidate is launched every iteration.** The sources launched per iteration follow this rule:

| Iteration | Sources to launch |
|---|---|
| `iter = 0` | **All candidates** |
| `iter ≥ 1` | "sources that reported at least one critical or major in the previous iteration" ∪ "`doc-drift-git` / `spec-audit-git` if `doc_dirty=true`" |

`doc_dirty` means "did the immediately preceding fix touch files under `docs/` or `*.md`" (updated in 2-5; `true` for certain at `iter=0`). Doc drift does not change when only code is fixed, so re-scanning in an iteration that did not touch docs is wasteful. Conversely, in an iteration that edited docs, the edit itself can create new drift, so re-run.

**For sources not launched, carry over the previous iteration's findings as-is into the threshold decision** (never treat "not launched" as "resolved").

By this rule, **an aspect that reported zero findings is not run from the second iteration on** (if `code-review-git` is clean in iteration 1, effectively it runs only the first time). The trade-off is that "side effects of the fix" that aspect would have caught may be missed (CI is the last line of defense).

`halt-review` / `atomic-review` have no diff variants, so pass as arguments only the paths in `changed_files` that match each skill's target extensions (`.templ` / `.go` / `.ts` / `.tsx` / `.vue`, etc.), limiting the scan range to the diff. If there are 0 matching paths, do not launch that skill.

## Phase 2: Review → Fix Loop

Each iteration launches one parallel subagent per review skill. Launch per `harness-model` (`subagent_type: review`; do not use `claude`; on Cursor do not pass `model`). **The main thread never touches code.**

### 2-1. Aggregate reviews (parallel)

Launch the chosen skills **in parallel within the same message**. Each agent runs exactly one specialist skill and returns findings as JSON.

**Scope constraints common to all agents** (always include in the prompt):
- Target only the `<base_ref>...HEAD` diff. Do not review files not in the diff
- Always anchor findings to a file:line inside the diff. Do not report pre-existing problems outside the diff
- If a serious problem is found outside the diff, put it in the `out_of_scope` array (not a fix target; only recorded in the report)
- Even for a finding inside the diff, if **fixing it requires changing a non-documentation file outside the diff** (implementation code, type definitions, CI / config files), put it in `out_of_scope` instead of a severity (the fix agent structurally cannot fix it). **A missing doc / spec update does not fall under this** — 2-4 permits editing them even outside the diff, so treat it as a normal finding

```
Agent({
  description: "refine-git iter <iter+1> — code-review-git",
  subagent_type: "review",
  prompt: """
Run /code-review-git-en on PR #<n> (branch: <branch>) via the Skill tool.
Pass the comparison branch <base_ref> as the argument.

Scope: only the <base_ref>...HEAD diff. Files outside the diff are out of review scope.
If asked for the output destination, choose "Console output" and do not create Issues.

Classify the findings by the severities below and return them as a single JSON line in the final message:
- critical: bugs, security problems, data corruption, test failures
- major: serious design flaws, performance degradation, public API inconsistencies
- minor: naming, comments, minor readability, style

Serious problems found outside the diff go into out_of_scope, not critical/major/minor.

{"source": "code-review-git", "critical": [{"file":"...", "line": N, "msg":"..."}], "major": [...], "minor": [...], "out_of_scope": [...]}
"""
})

# Launch only the sources matching the 1-9 launch rule (iter>=1: sources that reported critical/major last time + doc_dirty)
Agent({
  description: "refine-git iter <iter+1> — doc-drift-git",
  ... same as above, run /doc-drift-git-en with <base_ref>, return "source": "doc-drift-git"
})

Agent({
  description: "refine-git iter <iter+1> — spec-audit-git",
  ... same as above, run /spec-audit-git with `<base_ref> --report-only`, return "source": "spec-audit-git"
  # --report-only skips Issue creation and interaction; only the report is returned
})

# Only when HAS_HALT=true ∧ matching the launch rule (pass changed-file paths as arguments)
Agent({
  description: "refine-git iter <iter+1> — halt-review",
  ... run /halt-review-en <target paths within the diff>, return "source": "halt-review"
  # Do not let it scan anything other than the argument paths. Limit findings to the diff as well
})

# Only when HAS_ATOMIC=true ∧ matching the launch rule (pass changed-file paths as arguments)
Agent({
  description: "refine-git iter <iter+1> — atomic-review",
  ... run /atomic-review <target paths within the diff>, return "source": "atomic-review"
})
```

Aggregate each agent's returned JSON:

```bash
# Combine critical / major / minor of all sources (out_of_scope is not part of the threshold decision)
findings=$(printf '%s\n' "$resp_code" "$resp_doc" "$resp_spec" "$resp_halt" "$resp_atomic" | \
  jq -s '{
    critical: map(.critical // []) | flatten,
    major:    map(.major // [])    | flatten,
    minor:    map(.minor // [])    | flatten,
    out_of_scope: map(.out_of_scope // []) | flatten,
    by_source: map({(.source): {c:(.critical|length), m:(.major|length), mn:(.minor|length)}}) | add
  }')

# Drop findings anchored outside the diff (insurance in case a review agent ignored the scope)
findings=$(echo "$findings" | jq --argjson cf "$(printf '%s\n' "$changed_files" | jq -R -s 'split("\n") | map(select(length > 0))')" '
  def in_diff: select(.file == null or (.file as $f | $cf | index($f)));
  .critical |= map(in_diff) | .major |= map(in_diff) | .minor |= map(in_diff)')
```

`out_of_scope` is **included neither in the threshold decision nor in the fix targets** (only recorded in the Phase 3 report).

**For sources not launched under the 1-9 rule, reuse the previous iteration's response as-is and mix it into the aggregation.** Treating a non-launched source as empty would erase unresolved findings and wrongly reach the threshold.

### 2-2. Append telemetry + update state.json

Run "Per-iteration telemetry append + state.json update" in `references/state-and-telemetry.md` of `refine-en` (`source` becomes `refine-git`).

### 2-3. Threshold decision

```
if critical == 0 && major == 0 && (skip_minor || minor <= max_minor):
  → status=clean, go to Phase 3
if iter >= max_iter:
  → status=iter_limit, go to Phase 3 (finish with findings remaining)
if (critical + major) has not dropped below the previous value for 2 consecutive iterations:
  → status=no_progress, go to Phase 3
otherwise:
  → go to 2-4
```

**Pick status from the enum in `merge-and-report.md` (`clean` / `iter_limit` / `no_progress` / `agent_failed` / `merge_failed` / `ci_gave_up`). Never invent strings outside the enum such as `stuck`** (the calling `issue-sweep-en` parses it).

With `--skip-minor` (calls from `issue-sweep-en` always use it), minor is included neither in the threshold decision nor in the 2-4 fix targets. Minor means naming, comments, and readability, so each fix widens the diff and sprouts new minors, and the iteration keeps running to `max_iter`. If the caller's merge gate does not look at minor, that whole iteration is wasted.

**no_progress decision**: the previous value is in `last_counts` of state.json. If this iteration's `critical + major` is equal to or greater than the previous one, count one "stall"; **abort after 2 consecutive stalls** (not after 1, because fixes can temporarily add findings as a side effect). If it dropped, reset the stall count to 0.

Cycling the same findings accounts for most of the time up to `max_iter`, so hand unfixable findings back to a human early. The Phase 3 report MUST include `status: no_progress` and the findings remaining at the point of stall.

### 2-4. Fix agent

**Before** launching the agent, record `prev_head=$(git rev-parse HEAD)` in the main thread (used in 2-5 to get "the files touched by this fix").

```
Agent({
  description: "refine-git iteration <iter+1> fix",
  subagent_type: "develop",
  prompt: """
Fix the following findings on PR #<n> (branch: <branch>):

CRITICAL:
<list critical findings as file:line:msg>

MAJOR:
<list major findings>

MINOR (there are <minor - max_minor> excess minor findings; fix at least <minor - max_minor> of them, highest priority first):
<list minor findings>
(When `--skip-minor` is given, do not pass this MINOR block)

**Scope constraints (strict)**:
- You may change only the following files inside the diff:
  <list changed_files>
- **Exception 1 (documentation)**: files under `docs/**`, `*.md` at the repository root, and the spec directory
  **may be edited even outside the diff**. Findings from doc-drift-git / spec-audit-git are essentially
  "the code changed but the documentation did not follow", so if docs outside the diff could not be touched,
  they would be unfixable in principle. Treat documentation updates as the responsibility of that PR
- **Exception 2 (tests)**: adding new test files accompanying a fix is allowed (regression tests are mandatory)
- If changing any other file outside the diff (implementation code, type definitions, CI / config files) is unavoidable,
  do not fix it; return {"failure": "out_of_scope_required: <file> <reason>"} and defer the decision
- Even if you find another problem outside the diff, do not fix it. **Do not create Issues either** (do not call `/spinoff-issue-en`).
  Only record it in spinoff of the final JSON and move on. It is aggregated into
  `## Out of scope` of the Phase 3 report

Steps:
1. Switch with `git checkout <branch>`
2. Fix the findings in order (this agent itself is the develop agent)
3. Add tests where needed
4. Push the fix commit with `git push`
5. Final message JSON: {"fixed_critical": N, "fixed_major": N, "fixed_minor": N, "commit": "<sha>", "spinoff": ["<problem found outside the diff>"]}
   or on failure: {"failure": "<reason>"}
"""
})
```

On failure, abort the loop and go to Phase 3 with `status=agent_failed`.

### 2-5. Next iteration

The fix push widened the diff, so re-fetch `changed_files`:

```bash
prev_head=$(git rev-parse HEAD)   # ← the value recorded *before* the 2-4 fix push
merge_base=$(git merge-base "$base_ref" HEAD)
changed_files=$(git diff --name-only "$merge_base"...HEAD)
```

**From the second iteration on, narrow the review scope.** Most of the diff seen in iteration 1 was not changed by the fixes, so re-scanning the whole diff every time is wasteful:

```bash
# review scope = files touched by the previous fix ∪ files with unresolved findings
touched=$(git diff --name-only "$prev_head"...HEAD)
unresolved=$(echo "$findings" | jq -r '(.critical + .major + .minor)[].file // empty')
review_scope=$(printf '%s\n%s\n' "$touched" "$unresolved" | sort -u | grep -v '^$')
```

**Fix the launch targets for the next iteration** (1-9 rule):

```bash
# Did the immediately preceding fix touch docs
if echo "$touched" | grep -qE '^(docs/|.*\.md$)'; then doc_dirty=true; else doc_dirty=false; fi

# Sources that reported critical/major this time (the ones to re-run next iteration)
active_sources=$(echo "$findings" | jq -r '.by_source | to_entries[] | select(.value.c > 0 or .value.m > 0) | .key')
```

In the next iteration, pass each review agent `review_scope` instead of `changed_files` (the out-of-diff-anchor filter in 2-1 can stay on `changed_files`; scope judgment and viewing range are separate). `review_scope` is never empty (if it were empty, the threshold would have been met and 2-3 would already have succeeded).

Do `iter+=1` and return to Phase 2-1.

## Phase 3: Merge → Report Generation and Termination

Run steps 1–8 of `references/merge-and-report.md` in `refine-en`.

**Addition specific to this skill**: after the step 6 report generation, append an `## Out of scope` section:

```bash
cat >> "$report" <<EOF

## Out of scope（差分外で検出、未修正）

> refine-git は差分のみを修正対象とする。全体を磨くなら /refine または /refine-sweep を使う。

$(echo "$findings" | jq -r '.out_of_scope[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"' || echo "なし")
EOF
```

Also append the `spinoff` arrays returned by each iteration's fix agent to the same section (dedupe). This list is the material the user uses to decide "whether to file Issues", so **always output it unless empty**.

## Forbidden Actions

- **The main thread itself modifies code** (the CTO does not touch implementation — same principle as impl-wt and issue-sweep)
- Mixing the review agent and the fix agent in the same call (keep them independent)
- Ending the loop with "good enough" before the threshold is reached (the only allowed stops are reaching `max_iter` and the 2-3 no_progress decision)
- Looping infinitely past `max_iter`
- **Ignoring a stall (critical+major not dropping for 2 consecutive iterations) and running to `max_iter`** (cycling unfixable findings accounts for most of the elapsed time; hand back to a human early)
- **Re-scanning the whole diff from the second iteration on** (narrow to `review_scope` in 2-5; do not re-read unchanged files every time)
- Introducing side-effect bugs while fixing minors (if the post-fix review reports critical, continue iterating)
- **Launching a whole-repo scan review skill (`code-review` / `doc-drift` / `spec-audit`)** (always use the `-git` variants; if the whole-repo variant is needed, use `/refine-en` or `/refine-sweep-en`)
- **Launching `halt-review` / `atomic-review` without arguments** (it would scan the whole project; always pass the target paths within the diff as arguments)
- **Modifying files outside the diff** (do not omit the 2-4 scope constraints from the fix agent's prompt; problems outside the diff are only recorded in `out_of_scope` / `spinoff`). However, **2-4's Exception 1 (`docs/**` / `*.md` / specs) and Exception 2 (adding tests) may be edited even outside the diff**
- **Discarding a doc-drift-git / spec-audit-git finding without fixing it because "a file outside the diff is needed"** (docs are editable under 2-4's Exception 1; only cases that require out-of-diff changes to implementation code, type definitions, or config files may be demoted to `out_of_scope`)
- **Including minor in the threshold decision or fix targets when `--skip-minor` is given** (the `issue-sweep-en` merge gate does not look at minor, so that whole iteration is wasted)
- **Not carrying over the previous findings of a source not launched under the 1-9 rule, and judging the threshold as if they were resolved** (you would declare `clean` while holding unresolved findings)
- **Launching all candidate sources from the second iteration on** (follow the 1-9 table; running aspects that were clean last time every iteration accounts for a large part of the elapsed time)
- **Inventing a status name such as `stuck` that is not in the `merge-and-report.md` enum** (the caller cannot parse it; use `no_progress`)
- **Calling `/spinoff-issue-en` inside the fix loop** (the fix agent is launched up to `max_iter` times, so Issues would be mass-produced per iteration. Aggregate out-of-diff findings into `## Out of scope` of the report and let the user decide whether to file Issues)
- **Including `out_of_scope` findings in the threshold decision** (pre-existing problems outside the diff would keep the loop from ever converging)
- **Skipping some candidate sources in the first iteration (`iter=0`)** (the first iteration always covers every aspect; narrowing is allowed only from the second iteration on)
- **Skipping halt-review on a HALT project** (always launch in parallel when HAS_HALT=true)
- **Skipping atomic-review on an Atomic Design project** (always launch in parallel when HAS_ATOMIC=true; exclusivity with HAS_HALT=true is guaranteed by the detection side)
- **Continuing on a frontend project that has not adopted Atomic Design** (always abort at the Phase 1 IS_FRONTEND guard)
- **Declaring `clean` by estimation without confirming the final iteration's review result** (with `--no-merge`, use the final iteration's result as-is; do not run a confirmation re-review)
- **Overwriting `.sweep/state.json` owned by the calling sweep / setting `phase=terminal`** (see the guard in step 4 of `common-setup.md`; it is what makes the sweep's queue processing quietly end)
- **Skipping the merge although status=clean** (except when `--no-merge` is explicit)
- **Using `gh pr merge --auto`** (behavior depends on the repository's `allow_auto_merge` setting and stops with a GraphQL error when OFF; standardized on polling for CI green and then merging directly)
- Skipping the merge-completion check and moving on to report generation
- **Checking out in the main worktree to switch to the PR branch** (breaks worktree isolation and pollutes the main tree)
