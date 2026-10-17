---
name: refine-sweep-en
description: Review the whole codebase from 4-5 perspectives, file findings as Issues, work through them in worktrees, and run through PR/merge/close.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

**Source of truth: the Japanese `.claude/skills/refine-sweep` (Claude Code version) is canonical; this `-en` is a translation of it and MUST be updated after it. It is NOT translated from the `omp/skills/` version: differences in `omp/skills/` are not reflected, so calling this `-en` in omp lacks the omp-version fixes.**

# refine-sweep-en

The whole-codebase version of `/refine-git-en` (the difference from `/refine-en` is that fixes are turned into Issues and split across multiple PRs). It targets the entire repository rather than a specific PR, runs `/code-review-en` / `/doc-drift-en` / `/spec-audit-en` in parallel (plus `/halt-review-en` when HALT is detected, `/atomic-review` when Atomic Design is detected), **creates GitHub Issues** from the findings, then runs `/impl-en` one Issue at a time inside worktrees prepared by the sweep, carrying each through PR → merge → Issue close.

**Treat Issues as the Source of Truth for visibility.** Review creates Issues, and the engineer agent carries them through PR → merge → close. The CTO (main thread) focuses on state management and iteration decisions and never touches code.

## Arguments

- `/refine-sweep-en` — File Issues for all of critical + major + minor and work through them (default)
- `/refine-sweep-en --hard-cap N` — Physical upper limit on iteration count (default 30). Essentially a last safety net that is not normally reached
- `/refine-sweep-en --no-minor` — Do not file Issues for minor (lightweight mode)
- `/refine-sweep-en --max-minor N` — Number of minor Issues allowed to remain (default 5; 0 means fully consume). minor = `severity:medium` + `severity:low` (mapping table in Phase 1)
- `/refine-sweep-en --parallel <N>` — Upper limit on concurrently running implementation agents (default 5, max 5)
- `/refine-sweep-en --max-inflight <M>` — Upper limit on concurrently held unmerged PRs (default 10, max 15)
- `/refine-sweep-en --abort` — Abort the running sweep and delete the lock
- `/refine-sweep-en --single-pr` — **Single integration-branch mode.** Do not create a PR per Issue; stack everything on one integration branch and open just one PR to the base branch at the end (see "single-pr mode" below)
- `/refine-sweep-en --multi-pr` — The conventional mode that creates a PR per Issue
- `/refine-sweep-en --base <branch>` — Base branch (merge target of PRs)
- `/refine-sweep-en --branch <name>` — Integration branch name for single-pr mode. Default `sweep/refine-sweep-<YYYYmmdd-HHMMSS>`

**If `--single-pr` / `--multi-pr` and `--base` are not specified, always ask with `AskUserQuestion` in Phase P-0. Never decide by guessing.**

## Prerequisites

- `git`, `gh` CLI authenticated
- **GNU coreutils** (uses `date -d` / `timeout`). On macOS, `brew install coreutils` and put `gdate` / `gtimeout` on PATH
- The base branch is **confirmed with the user in Phase P-0** (`../sweep-common-en/branch-preflight.md`). Never adopt the result of `git branch --show-current` as the base by guessing
- Write permission to `$SWEEP_DIR/`
- Labels `refine-sweep` and `refine-sweep-iter-<N>` are created automatically as needed

## State Management `$SWEEP_DIR/state.json`

Progress-state file common to the sweep family of skills. The Stop Hook (`check-sweep-state.sh`) blocks stopping while `phase != "terminal"` (as long as the lock is fresh). **Never set `phase=terminal` by estimation without re-running review.** Immediately before marking terminal, run a final review and confirm that its line has been appended to `$SWEEP_DIR/refine-metrics.jsonl`.

**The audit trail is `refine-metrics.jsonl` alone.** The `evidence` array in state.json that mirrored line numbers and the `last_counts` that duplicated raw review counts have been removed (same decision as issue-sweep. The Stop Hook decides only from `phase` and lock freshness; both were used only for display).

**Schema:**
```json
{
  "skill": "refine-sweep",
  "started_at": "<ISO8601>",
  "updated_at": "<ISO8601>",
  "phase": "iterating" | "terminal",
  "iteration": <N>,
  "hard_cap_iter": <N>,
  "thresholds": {"critical": 0, "major": 0, "minor": <max_minor>},
  "termination_reason": null | "thresholds_met" | "hard_cap_reached" | "agent_failed" | "fix_ineffective" | "aborted"
}
```

**Update timing:**
- At the start of Phase 0/1, initialize with `phase=iterating, iteration=0`
- At 2-3 of each iteration (right after review), update `iteration` (counts are written only to `refine-metrics.jsonl`)
- In Phase 3, set `phase=terminal` and `termination_reason`. **Run a final review immediately before, and mark terminal only after confirming its line was appended to `refine-metrics.jsonl`**

## single-pr mode (`--single-pr`)

**Do not create a PR per Issue; stack all iterations onto the one integration branch cut at the start, and open just one PR to the base branch at the end.** When enabled, **read `../sweep-common-en/single-branch-mode.md` first**, then enter Phase 0 (`skill_name="refine-sweep"`). The phase order is:

`Phase 0 (lock) → P-0 (confirm mode & base) → S-0 (create integration branch) → Phase 1 → Phase 2 iterations (apply S-1 diff) → 3-1 (double-confirm) → S-2 (integration polish, final PR, CI check) → S-3 (report)`

The differences from normal mode are only the following places:

| Place | Replacement in single-pr |
|---|---|
| Right after P-0 | Run S-0. Cut the integration branch from the base confirmed in P-0 and push it |
| Phase 1 step 1 | `base_branch` is already confirmed in P-0. The main worktree stays on the integration branch (do not re-fetch from `git branch --show-current`) |
| state.json in Phase 0 step 3 | Add `mode` / `base_branch` / `int_branch` / `pr_number` / `integrated_count` (S-0-3) |
| Base refresh in 2-1 | **Do not advance the integration branch** instead of `git pull --ff-only origin "$base_branch"`. If base updates must be brought in, explicitly do `git merge --no-ff origin/$base_branch` |
| Review in 2-2 | No change. The main worktree is the integration branch, so each iteration's review automatically sees "the integrated state" |
| Engineer agent in 2-5-3 | Change the worktree's branch-off point from `$base_branch` to **`$int_branch`**. The agent goes only as far as `/impl #<issue_num> --auto --no-pr` (the Japanese `/impl`: `/impl-en` does not implement `--auto` / `--no-pr`) (**do not let it run polishing** — `/refine-git-en` runs once on the integration branch in S-2-0). **Do not let it do any of** PR creation, CI wait, merge, or Issue close. The reply JSON is `{"issue":N,"domain":"...","work_branch":"...","worktree":"...","failure":null}` |
| Decision in 2-5-4 | **Agent reply → integration merge** (S-1, always serial) instead of observing PR state. No PR exists, so the PR-list fetch in 2-5-1 is unnecessary (heartbeat and base refresh only). Read `closed_count` as `integrated_count` |
| Issue close in 2-5-5 | Do not close. **The final PR is not merged by the sweep, so the Issues are not closed either** (S-3 only lists them as "Issues to close after merge"). The `fix_ineffective` decision, if left as a fingerprint comparison of open Issues, would misfire because integrated Issues stay open, so **compare over the set excluding integrated Issues** |
| Completion in 3-2 | Run S-2 → S-3, then write the report. The Summary MUST include the mode, base, integration branch, and PR URL (**still open**) |

## Phase 0: Acquire Lock (heartbeat method)

**The Bash tool uses a fresh shell per call**, and neither variables nor functions carry over. `$base_branch` / `$int_branch` / `assert_not_base` are **re-read every time from `$SWEEP_DIR/prelude.sh`, generated by P-0-0** (`../sweep-common-en/branch-preflight.md`). Every bash snippet that uses them starts with these 2 lines:

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
source "$SWEEP_DIR/prelude.sh"
```

1. If `$SWEEP_DIR/lock` exists and its timestamp is within 2 hours → show "another sweep is running" and exit
2. Otherwise `mkdir -p "$SWEEP_DIR" && echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"`
3. Initialize `$SWEEP_DIR/state.json`:
   ```bash
   jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson hc "$hard_cap" --argjson mm "$max_minor" '{
     skill: "refine-sweep",
     started_at: $now, updated_at: $now,
     phase: "iterating", iteration: 0, hard_cap_iter: $hc,
     thresholds: {critical: 0, major: 0, minor: $mm},
     termination_reason: null
   }' > "$SWEEP_DIR/state.json"
   ```
4. On Phase 3 / abort / `--abort`, `rm -f "$SWEEP_DIR/lock"`. **Leave `$SWEEP_DIR/state.json` in place** (for history/audit), but always set `phase=terminal` before leaving

## Phase P-0: Confirm Mode and Base Branch (mandatory)

**Read `../sweep-common-en/branch-preflight.md` and execute exactly its steps. Never skip.**
Only when both `--single-pr` / `--multi-pr` and `--base` are fixed by arguments may the interview (P-0-2) be omitted.

What is fixed here:

- `mode` (`single-pr` = one integration branch + one final PR / `multi-pr` = a PR per Issue)
- `base_branch` (merge target of PRs. **Never adopt the result of `git branch --show-current` by guessing**)
- `main_worktree` and the preflight guard function `assert_not_base`

If `mode=single-pr`, continue to S-0; if `multi-pr`, go to Phase 1.

## Phase 1: Environment Preparation

1. `base_branch` is already confirmed in P-0 (`base_branch` in state.json). Do not re-fetch it here
2. **HALT detection**:
   - A `*.templ` file exists or the spec mentions "HALT / HTMX+Atomic+Lit+Templ" → `HAS_HALT=true`
3. **Atomic Design detection** (only when HAS_HALT=false):
   - Any of `components/`, `src/components/`, `app/components/` has `atoms/` + (`molecules/` or `organisms/`) → `HAS_ATOMIC=true`
4. **Mandatory Atomic Design guard for frontend projects**:
   - `package.json` contains a dependency on `react` / `vue` / `next` / `nuxt` → `IS_FRONTEND=true`
   - `IS_FRONTEND=true` and `HAS_HALT=false` and `HAS_ATOMIC=false` → **abort here** (write `termination_reason: "atomic_design_required"` to `$SWEEP_DIR/state.json`, set `phase=terminal`, exit 2)
5. **Review skill list**:
   - Always: `code-review-en`, `doc-drift-en`, `spec-audit-en`
   - `HAS_HALT=true`: also add `halt-review-en`
   - `HAS_ATOMIC=true`: also add `atomic-review`
6. **Mapping between severity labels and importance (the single definition; do not re-interpret elsewhere)**:

   | Internal term | Label | Merge gate | Counted by `--max-minor` |
   |---|---|---|---|
   | critical | `severity:critical` | 0 required | — |
   | major | `severity:high` | 0 required | — |
   | minor | `severity:medium`, `severity:low` | not checked | counted |

   **Every label always falls into one of the buckets.** An unknown severity value is treated as minor (do not tighten the gate on your own).

7. **Label preparation** (create if absent, no-op if existing):
   ```bash
   gh label create refine-sweep --color BB6BD9 --description "created by /refine-sweep" 2>/dev/null || true
   for sev in critical high medium low; do
     gh label create "severity:${sev}" --color EEEEEE 2>/dev/null || true
   done
   ```
8. Initialize `start_ts=$(date +%s)`, `iter=0`, `hard_cap=30`, `include_minor=true`, `max_minor=5` (`include_minor=false` only with `--no-minor`; `--hard-cap` / `--max-minor` can override)

## Phase 2: Review → File Issues → Work-Through Loop

### 2-1. Start of iteration

```bash
source "$SWEEP_DIR/prelude.sh"
echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"          # heartbeat
git fetch origin "$base_branch" 2>/dev/null || true
git pull --ff-only origin "$base_branch" 2>/dev/null || true
iter_label="refine-sweep-iter-$((iter+1))"
gh label create "$iter_label" --color 0E8A16 2>/dev/null || true
```

### 2-2. Run reviews in parallel (have them file Issues)

Launch each review skill **in Issue-filing mode in parallel**. Launch per `harness-model` (`subagent_type: review`). The sub-agent calls the Skill, and any `AskUserQuestion` inside the Skill automatically selects `GitHub Issue` (labelled "Create GitHub Issues" in spec-audit-en) + `Individual Issues` and proceeds.

```
Agent({
  description: "refine-sweep iter <iter+1> — code-review",
  subagent_type: "review",
  prompt: """
Run /code-review-en on the whole repository via the Skill tool.

**Issue-filing policy (strict)**:
- File the detected findings as **GitHub Issues** (use the review skill's native behavior)
- If the Skill asks for the output destination via AskUserQuestion, choose **"GitHub Issue"**
- If asked for the Issue creation mode, choose **"Individual Issues"** (1 finding = 1 Issue)
- If asked for approval confirmation, **approve** and move on
- Do not stop for additional confirmation from the user

**Labels that MUST be attached to Issues**:
- `refine-sweep` (common identifier)
- `<iter_label>` (identifies this iteration, e.g. `refine-sweep-iter-3`)
- severity label (`severity:critical` / `severity:high` / `severity:medium` / `severity:low`)
- skill-specific label (e.g. `code-review`)

If `--no-minor`-equivalent is instructed, do not file Issues for minor-equivalent (severity:low). This time's setting: <include_minor>

**Reply JSON (one line only)**:
{"source":"code-review","issue_numbers":[<Issue numbers newly created this time>],"counts":{"critical":N,"major":N,"minor":N},"failure":null}

On failure: {"source":"code-review","issue_numbers":[],"counts":{"critical":0,"major":0,"minor":0},"failure":"<reason>"}

Reply rules:
- Include nothing other than the one JSON line in the final message
- Do not leave internal logs in the main thread
"""
})

# /doc-drift-en, /spec-audit-en likewise (swap source; skill-specific labels are doc-drift / spec-audit)
# Only when HAS_HALT=true, launch /halt-review-en likewise in parallel (source="halt-review")
# Only when HAS_ATOMIC=true, launch /atomic-review likewise in parallel (source="atomic-review")
```

Aggregate each agent's reply:

```bash
new_issues=$(printf '%s\n' "$resp_code" "$resp_doc" "$resp_spec" "$resp_halt" "$resp_atomic" | \
  jq -s 'map(select(. != null and . != "")) | {
    issues: (map(.issue_numbers // []) | flatten | unique),
    counts: {
      critical: (map(.counts.critical // 0) | add),
      major:    (map(.counts.major // 0) | add),
      minor:    (map(.counts.minor // 0) | add)
    },
    by_source: (map({(.source): (.counts // {})}) | add),
    failures: (map(select(.failure != null) | {source, failure}))
  }')

if [[ $(echo "$new_issues" | jq '.failures | length') -gt 0 ]]; then
  # if even one review agent failed → go to Phase 3 with agent_failed
  status="agent_failed"
fi
```

### 2-3. Append telemetry + update state.json (right after review)

```bash
new_issue_count=$(echo "$new_issues" | jq '.issues | length')
open_issue_count=$(gh issue list --label refine-sweep --state open --limit 500 --json number | jq 'length')

jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson iter "$iter" \
  --argjson new_ic "$new_issue_count" \
  --argjson open_ic "$open_issue_count" \
  --argjson counts "$(echo "$new_issues" | jq .counts)" \
  --argjson by_src "$(echo "$new_issues" | jq .by_source)" \
  --argjson halt "$HAS_HALT" \
  '{ts:$ts,source:"refine-sweep-review",iter:$iter,new_issues:$new_ic,open_issues:$open_ic,counts:$counts,by_source:$by_src,halt:$halt}' \
  >> "$SWEEP_DIR/refine-metrics.jsonl"

jq --argjson iter "$iter" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.iteration = $iter | .updated_at = $now' \
   "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
```

**Evidence rule**: in each iteration, append at least 1 line (`source: "refine-sweep-review"`) to `refine-metrics.jsonl`. **Never let it proceed to Phase 3 with zero lines.**

### 2-4. Threshold decision

**The basis for the decision is the label tally of open Issues** (not the "new count this time" the review agent returned — that would miss critical findings left over from earlier iterations):

```bash
source "$SWEEP_DIR/prelude.sh"
counts=$(gh issue list --label refine-sweep --state open --limit 500 --json labels \
  | jq -c '[.[] | [.labels[].name]] as $all
    | { critical: ([$all[] | select(index("severity:critical"))] | length),
        major:    ([$all[] | select(index("severity:high"))]     | length),
        minor:    ([$all[] | select(index("severity:critical") or index("severity:high") | not)] | length),
        open:     ($all | length) }')
eval "$(echo "$counts" | jq -r '@sh "critical_open=\(.critical) major_open=\(.major) minor_open=\(.minor) open_issue_count=\(.open)"')"
```

`minor_open` is every open Issue other than critical / high (`severity:medium` / `severity:low` / no severity). **To leave no gaps, minor is defined as "neither critical nor major".**

```
if iter >= hard_cap:
  → hard_cap_reached, go to Phase 3

elif critical_open == 0 && major_open == 0
     && (include_minor == false || minor_open <= max_minor)
     && new_issue_count == 0:
  → clean candidate, go to the Phase 3-1 double-confirm

else:
  → go to 2-5 (work through Issues)
```

With `--no-minor`, minor is merely not filed as Issues, and **minor Issues created in the past are excluded from the decision** (with `include_minor == false`, do not look at `minor_open`).

Only reaching `hard_cap` is a physical cutoff. Otherwise, defer to the `fix_ineffective` decision and keep going.

### 2-5. Work through Issues (in-flight pipeline)

Carry every open Issue with label=`refine-sweep` all the way through **worktree work → PR → CI green → merge → Issue close**.

**The structure is the same as Phase 2 of issue-sweep** (batches map to Issues, and the base branch is the same). The main thread only does "queue operations / fetching the PR list / launching agents / decisions / merging / failure handling", and **always delegates implementation to an `Agent`**.

- `--parallel N` (default 5, max 5) = number of implementation agents running concurrently
- `--max-inflight M` (default 10, max 15) = number of unmerged PRs held concurrently

**Do not build a wave barrier ("implement N → wait for all CI → another N").** On a project where CI takes 10 minutes, that barrier becomes exactly "10 minutes with 0 implementation agents". Launch the next Issue the moment a slot frees up.

#### 2-5-0. Queue construction and domain inference

Write the open Issues to `$SWEEP_DIR/queue.txt`, one Issue per line. Extract file paths from each Issue's body (regex `[a-zA-Z0-9_./-]+\.(go|ts|tsx|js|jsx|vue|sql|md|yaml|yml)`) and infer the domain:

- `db`: `migrations/`, `schema.sql`, `db/`, `prisma/`
- `backend`: `apps/api/`, `api/`, `src/server/`, `*.go`
- `frontend`: `apps/web/`, `web/`, `src/components/`, `*.tsx`, `*.jsx`, `*.vue`
- `ci`: `.github/workflows/`, `ci/`, `Dockerfile`
- `other`: matches none of the above or paths cannot be extracted

**Use the domain only for deciding parallelizability** (2-5-2). The in-flight table has the same columns as issue-sweep's with `domain` added, and is carried around as text within messages:

| Column | Content |
|---|---|
| `issue` / `domain` / `branch` / `pr` / `stage` / `ci_respawns` / `zero_check_rounds` / `worktree` / `start_ts` | Same as Phase 2 of issue-sweep |

#### 2-5-1. Start of round (heartbeat / base refresh / bulk-fetch PR list)

```bash
source "$SWEEP_DIR/prelude.sh"
echo "$PPID:$(date +%s)" > "$SWEEP_DIR/lock"
git fetch origin "$base_branch" 2>/dev/null || true
git pull --ff-only origin "$base_branch" 2>/dev/null || true

# Fetch this round's PR info in **just one call** (both the idempotency check and the state decision use it).
# Narrow to PRs created by refine-sweep with `head:refine/`
gh pr list --search "head:refine/" --state all --limit 100 \
  --json number,headRefName,state,mergedAt,statusCheckRollup \
  | jq -c '[.[] | {
      pr: .number, branch: .headRefName, state: .state, merged: (.mergedAt != null),
      failed_checks: [.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name],
      waiting: ([.statusCheckRollup[]? | select(.conclusion == null and .status != "COMPLETED")] | length),
      checks_total: ([.statusCheckRollup[]?] | length)
    }]'
```

#### 2-5-2. Slot refill (launch)

If `running < N` and `in_flight < M` and the queue still has **launchable** Issues, launch as many as there are free slots.

Launch conditions (the domain is used only to avoid PR conflicts):

- **No Issue of the same domain is in flight** (serial within the same domain)
- The `db` domain launches **only when in-flight is 0**. Conversely, while `db` is in flight, launch nothing else
- Do not launch Issues with the `refine-sweep-stuck` label

**Idempotency check** (look for `branch == "refine/issue-<N>"` in the 2-5-1 list; make no additional `gh` calls):

- `merged == true` → do not launch an agent; go to 2-5-5 (close → remove from queue)
- `state == "OPEN"` → a PR already exists. Skip agent launch and put it in in-flight with `stage=ci` under that PR number
- Not found → launch via 2-5-3

#### 2-5-3. Launch the implementation agent

**The sweep creates one worktree first, then fills in the path and passes it** (do not have it call `/impl-wt`. Calling it creates the worktree twice, and since it lacks `--no-pr` the PR would also be created twice):

```bash
source "$SWEEP_DIR/prelude.sh"
wt="$(dirname "$main_worktree")/$(basename "$main_worktree")-refine-<issue_num>"
git worktree add "$wt" -b "refine/issue-<issue_num>" "$base_branch"   # for single-pr, the branch-off point is "$int_branch"
assert_not_base "$wt" || { echo "guard 失敗: この Issue は諦める"; }
```

If `git worktree add` fails, **do not launch that Issue** and treat it as a failure (never let it do substitute work in the main repository).

```
Agent({
  description: "refine-sweep iter <iter+1> #<issue_num> [<DOMAIN>]",
  subagent_type: "develop",
  prompt: """
Implement Issue #<issue_num> and create one PR. Return only JSON to the main thread.
The worktree is already created. **Do all further work inside <absolute path of wt>.**

Steps:
0. Always run this before starting work:
   cd <absolute path of wt>
   cur=$(git rev-parse --abbrev-ref HEAD)
   [[ "$cur" != "<base_branch>" && "$cur" != "main" && "$cur" != "develop" ]] || exit 2
   If this fails, **you must not implement in the main repository instead**. Return a failure JSON and exit immediately.
   Repeat the same check once more before the first `git commit`.
1. Launch `/impl #<issue_num> --auto --no-pr` via the Skill tool to implement (the Japanese `/impl`: `/impl-en` does not implement `--auto` / `--no-pr`).
   **Do not use the wt variant (`/impl-wt`)** (the worktree is already created; calling it would create it twice).
   `--auto` = do not stop to ask for confirmation / `--no-pr` = you create exactly one PR yourself in step 2.
2. Push and create exactly one PR with `gh pr create --base <base_branch>`.
   Link it with `gh pr edit <PR> --add-issue <Issue URL>` (do not use `Closes`).
3. **Return as soon as the PR is created.** Waiting for CI, merging, and closing the Issue are the main thread's responsibility, so do none of them.

Success: {"issue": <issue_num>, "domain": "<DOMAIN>", "pr_number": <N>, "pr_url": "<URL>", "branch": "refine/issue-<N>", "worktree": "<absolute path of wt>", "failure": null}
Failure: {"issue": <issue_num>, "domain": "<DOMAIN>", "pr_number": null, "worktree": "<absolute path of wt>", "failure": "<cause in one line>"}

Strict rules:
- **Always assign any Issue you start to yourself with `gh issue edit <issue_num> --add-assignee @me`**
  (`/impl` Phase 1 has this step, but `--auto` prioritizes not stopping, so this non-blocking
  bookkeeping is easy to drop. Always pass the assignee check of the verification gate)
- Do not read or modify `$SWEEP_DIR/state.json` (the refine-sweep main thread manages it exclusively)
- Do not touch `$SWEEP_DIR/lock`
- Do not recursively launch `/issue-sweep-en` or `/refine-sweep-en` (state collision)
- **Do not run `gh pr merge` / do not run `gh issue close`** (merge and close are the main thread's)
- Include nothing other than the one JSON line in the final message
- Do not leave internal logs in the main thread
- Do not stop for user confirmation
"""
})
```

#### 2-5-4. Decision and execution (main thread)

**Use the table from "Decision and execution" in Phase 2 of issue-sweep-en as-is** (`merged` / manual close / CI confirmed failure / the `checks_total == 0` cat-stepping guard / merge / not found in the list / otherwise). The CI fix agent's launch prompt is also the same; just swap the branch to `refine/issue-<N>`. Decisions and agent relaunches are done **on the LLM side** (an `Agent` cannot be called from inside a bash `while`).

#### 2-5-5. Issue close + queue removal + metrics

After the merge completes:

```bash
gh issue close "<issue_num>" --comment "Closed by PR #<PR> (via /refine-sweep iter <iter>)" || true
grep -vxF "<issue_num>" "$SWEEP_DIR/queue.txt" > "$SWEEP_DIR/queue.tmp" && mv "$SWEEP_DIR/queue.tmp" "$SWEEP_DIR/queue.txt"
jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" --argjson iter "$iter" \
   --argjson issue "<issue_num>" --arg domain "<DOMAIN>" --argjson pr "<PR>" --arg status "merged" \
   '{ts:$ts,source:"refine-sweep-consume",iter:$iter,issue:$issue,domain:$domain,pr_number:$pr,status:$status}' \
   >> "$SWEEP_DIR/refine-metrics.jsonl"
```

#### 2-5-6. Worktree cleanup

Delete the `worktree` path the agent returned as-is (**always** delete it even on `failure`; otherwise names collide when the same Issue is retried next iteration):

```bash
git worktree remove --force "<worktree>" 2>/dev/null || true
```

#### 2-5-7. On failure (stuck decision)

An Issue where the agent returned `failure` / CI was given up on is **abandoned and removed from the queue** for that iteration (1 iteration = 1 attempt per Issue; leaving it would make the Stop Hook block stopping forever). Record `status` in metrics, and keep the failed Issue numbers in a per-iteration file:

```bash
echo "$failed_ids" > "$SWEEP_DIR/failed-iter-${iter}.txt"
prev="$SWEEP_DIR/failed-iter-$((iter-1)).txt"
if [[ -f "$prev" ]]; then
  # Issues that failed 2 iterations in a row get labeled stuck and are excluded from the next iteration
  for id in $(comm -12 <(sort "$prev") <(sort "$SWEEP_DIR/failed-iter-${iter}.txt")); do
    gh issue edit "$id" --add-label "refine-sweep-stuck" 2>/dev/null || true
  done
fi
```

#### 2-5-8. Wait and end of iteration

Only when this round made no progress (0 merges, 0 new launches) and in-flight remains, run **`sleep 60` inside a single bash command** and then return to 2-5-1. If there was progress, go straight to the next round without waiting.

**Never end the turn by saying "waiting."** (every time the Stop Hook pushes back, it consumes one model turn).

**When the queue is empty ∧ in-flight is 0, this iteration ends.** Fix `closed_count` / `failed_ids` and proceed to the fix_ineffective decision below.

**fix_ineffective decision (Issue fingerprint-set comparison)**:

At the end of each iteration, save the fingerprint set of open Issues with label=`refine-sweep` and label≠`refine-sweep-stuck`, and compare with the previous iteration:

```bash
gh issue list --label refine-sweep --state open --limit 500 --json number,title,body,labels \
  | jq -c '[.[] | select((.labels // []) | map(.name) | index("refine-sweep-stuck") | not)
           | (.title + "|" + (.body // "" | tostring))] | sort | unique' \
  > "$SWEEP_DIR/issues-iter-${iter}.json"

prev_file="$SWEEP_DIR/issues-iter-$((iter-1)).json"
if [[ "$iter" -ge 1 && -f "$prev_file" ]]; then
  curr=$(cat "$SWEEP_DIR/issues-iter-${iter}.json")
  prev=$(cat "$prev_file")
  if [[ "$curr" == "$prev" && "$curr" != "[]" ]]; then
    status="fix_ineffective"
    break
  fi
fi
```

- Issue set exactly equal to the previous iteration → abort (working through them is genuinely not helping)
- 3 closed by working through, 3 newly found by new review (title/body differ) → the set differs, so **continue**
- Do not decide by count alone (abort only on fingerprint match)

Do `iter += 1` and return to 2-1.

## Phase 3: Completion

### 3-1. double-confirm review (only for clean candidates)

For a clean candidate (`open_issue_count == 0 && new_issue_count == 0`, or within the minor allowance), **run the same parallel review as 2-2 once more** (a pure re-review with no consume):

- Append the result to `$SWEEP_DIR/refine-metrics.jsonl` (this line becomes the evidence that "the final review was actually run")
- 2 consecutive times with new Issues = 0 → status=`clean` confirmed, go to 3-2
- New Issues appear on the 2nd run → reviewer fluctuation or a missed detection. Do not trust the first 0; return to Phase 2-5 and work through them (`iter += 1`, as long as `hard_cap` is not reached)

### 3-2. Completion

1. Tidy leftover worktrees with `git worktree prune`
2. **Mark state.json terminal**:
   ```bash
   reason="thresholds_met"   # or hard_cap_reached / agent_failed / fix_ineffective / aborted
   jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
     "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
   ```
3. Generate the report `$SWEEP_DIR/report-refine-sweep-<ts>.md` (**the `## Evidence` section is mandatory**):

```bash
source "$SWEEP_DIR/prelude.sh"
ts=$(date -u +%Y%m%dT%H%M%SZ)
report="$SWEEP_DIR/report-refine-sweep-${ts}.md"
mkdir -p "$SWEEP_DIR"
# The iteration counter and start time do not persist in the shell. Read them from state.json
eval "$(jq -r '@sh "iter=\(.iteration) started_at=\(.started_at) reason=\(.termination_reason // "-")"' "$SWEEP_DIR/state.json")"
elapsed=$(( $(date +%s) - $(date -d "$started_at" +%s) ))
{
  echo "# refine-sweep report — $(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "## Summary"
  echo "- Base branch: ${base_branch}"
  echo "- Iterations: ${iter}"
  echo "- Final status: **${status}** (reason: ${reason})"
  echo "- Elapsed: ${elapsed}s"
  echo
  echo "## Issue trend"
  echo
  echo "| Iter | New | Closed | Open (end) | Critical | Major | Minor |"
  echo "|---|---|---|---|---|---|---|"
  jq -rs '(map(select(.source == "refine-sweep-consume")) | INDEX(.iter | tostring)) as $c
    | map(select(.source == "refine-sweep-review"))[]
    | "| \(.iter) | \(.new_issues) | \($c[.iter | tostring].closed // "-") | \(.open_issues) | \(.counts.critical) | \(.counts.major) | \(.counts.minor) |"' "$SWEEP_DIR/refine-metrics.jsonl"
  echo
  echo "## Evidence（review 実行の証跡）"
  echo
  jq -r 'select(.source == "refine-sweep-review") | "- iter \(.iter) @ \(.ts): new=\(.new_issues) open=\(.open_issues)"' "$SWEEP_DIR/refine-metrics.jsonl"
  echo
  echo "## Remaining open issues"
  gh issue list --label refine-sweep --state open --limit 500 --json number,title,labels \
    | jq -r '.[] | "- #\(.number) \(.title) [labels: \((.labels // []) | map(.name) | join(", "))]"'
  echo
  echo "## Stuck issues (skipped after 2 consecutive failures)"
  gh issue list --label refine-sweep-stuck --state open --limit 500 --json number,title \
    | jq -r '.[] | "- #\(.number) \(.title)"'
} > "$report"
```

4. `rm -f "$SWEEP_DIR/lock"` (leave state.json as terminal)
5. Notify: `sweep_notify "refine-sweep done" "${iter} iters, status=${status}, report: ${report}" ":checkered_flag:"`
6. Return the report path to the user

## Forbidden Actions

**Do not repeat what the body's steps already say.** What is here are only the traps you can still step on even when following the steps as written.

**Branch**

- **Adopting the result of `git branch --show-current` as the base branch by guessing** (the starting point is the user's decision)
- **Automatically repairing a state that tripped the preflight guard with `git reset` / `git checkout -f` and continuing** (hand it back to a human)
- **Assuming shell variables (`$base_branch` / `$iter` / `$start_ts`, etc.) persist until the next Bash call** (each call is a fresh shell. Source the prelude, and read counters from state.json)

**Delegation to agents**

- **The main thread itself modifies code / commits / edits PRs** (the CTO does not touch implementation)
- **The main forgetting to merge after CI green / removing from in-flight without confirming merge completion** (the agent returns once the PR is created, so unless the main observes it the PR gets buried)
- **Merging the PR without closing the Issue** (the main MUST run `gh issue close` right after merge)
- **Leaving a placeholder that cannot be filled in the agent prompt (`<worktree_path>`, etc.)** (the agent cannot run the guard, and the entire detection of direct commits to the base branch falls)
- **Stopping the review agent from creating Issues** (old design. Issue filing is now the intended design)
- **Treating `checks_total == 0` as "CI green" and merging** (right after PR creation no check is registered yet. Judge "no CI" only after confirming 0 for 2 consecutive rounds)
- **Ending the turn and waiting when there is nothing to do** (every time the Stop Hook pushes back, it consumes one model turn. When waiting, put `sleep 60` inside a single bash command)

**Iteration and termination**

- **Aborting early based on iteration count** (abort only via `fix_ineffective` or `hard_cap`) / looping infinitely even after reaching `hard_cap`
- **Skipping minor by default** (only when `--no-minor` is explicit)
- **Not re-running the final review before `phase=terminal`**
- **Reviving `evidence` / `last_counts` in state.json** (the audit trail is `refine-metrics.jsonl` alone. Double-managing leads to updating only one side) / not writing the `## Evidence` section in the report
- **Removing the `refine-sweep-stuck` label on your own** (keep it until a human decision is made)
- **Stopping to ask the user for confirmation** ("shall I continue?", "proceed to the next iteration?", "how much parallelism?". Proceed with defaults for everything. The Stop Hook pushes back)

**single-pr mode**

- When `--single-pr` is given, proceeding without reading `../sweep-common-en/single-branch-mode.md` (do not infer the steps from the diff table alone)
- **Creating a PR per Issue / running integration merges in parallel / waiting for CI on every integration** (details in that reference's forbidden actions)

## Behavior on Failure

- review agent failure (even one returns `failure != null`): record `agent_failed` and go to Phase 3
- engineer agent failure on the same Issue for 2 consecutive iterations: attach the `refine-sweep-stuck` label, exclude it from the next iteration, and continue
- All open Issues are stuck: list them in the report and mark terminal
- The same Issue set (fingerprint set) exactly matches for 2 consecutive iterations: finish with `fix_ineffective`
