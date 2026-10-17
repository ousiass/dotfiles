# single-pr mode (1 integration branch → 1 PR)

Spec for the consolidation mode shared by `issue-sweep-en` / `refine-sweep-en` / `spec-sweep` / `report-sweep`.
The calling SKILL.md sets `skill_name` beforehand.

**There are only 2 differences from normal mode**:

1. Do not create a PR per work unit (batch / Issue / spec item); **stack everything on the one integration branch cut at the start, and open only one PR to the base branch at the end**
2. **Do not run polish (`/refine-git-en`) per work unit; run it only once against the integration branch after everything is stacked** (phase S-2-0)

Queue management, lock, state.json, metrics, and spinoff following stay as in normal mode.

## Common arguments

- `--single-pr` — enable this mode (**if not specified, always ask the user in P-0**. See `branch-preflight.md`)
- `--base <branch>` — base branch (PR merge target). **If not specified, always ask in P-0**
- `--branch <name>` — integration branch name. Default `sweep/<skill_name>-<YYYYmmdd-HHMMSS>`

## Phase S-0: Create the integration branch

Run right after phase P-0 (confirm mode and base branch) of `branch-preflight.md` and **before** queue construction (phase 1).

### S-0-1. Base branch

**Already confirmed in P-0** (`$base_branch` and `base_branch` in state.json). Do not ask again here.

### S-0-2. Cut the integration branch and push it

```bash
source "$SWEEP_DIR/prelude.sh"
int_branch="${branch_opt:-sweep/${skill_name}-$(date +%Y%m%d-%H%M%S)}"   # held manually until persisted to state.json in S-0-3
git checkout -B "$int_branch" "origin/$base_branch"
assert_not_base "$main_worktree"   # pre-guard of branch-preflight.md
git push -u origin "$int_branch"
```

- **The main working tree stays on `$int_branch` from here on.** Never return to the base branch
- Push the empty integration branch at this point (work-unit worktrees branch from it, and results remain on the remote even if a crash happens midway)

### S-0-3. Add mode info to state.json

Initialize by adding the following to the normal-mode schema:

```json
{ "mode": "single-pr", "base_branch": "<base>", "int_branch": "<int>", "pr_number": null, "integrated_count": 0 }
```

**Once written here, `$int_branch` becomes readable from every snippet via the prelude.** Do not carry it in shell variables from here on.

## Phase S-1: Integration for implementation sweeps (issue-sweep / refine-sweep)

Run phase 2 of normal mode (in-flight pipeline) as is. The differences are only the following.

### At launch (differences in the agent prompt)

- The worktree branches from **`$int_branch`, not the base branch**:
  `git worktree add <path> -b <work_branch> "$int_branch"`
- **Do not let it create a PR.** Forbid `gh pr create`, and stop at commit + push using sub-skills with `--no-pr` (`/impl #<n> --auto --no-pr` etc.; the Japanese sub-skills, because the `-en` ones do not implement `--auto` / `--no-pr`)
- **Do not launch per-work-unit polish (`/refine-git-en`).** Polish runs only once on the integration branch in S-2-0.
  Running it per work unit would (a) detect and fix the same findings separately as many times as there are work units, which is entirely wasted, and
  (b) see only each work unit's own diff, so **nobody sees inter-batch duplication, API inconsistency, or integration-caused degradation**
- The work-unit gate is **the tests and lint that the sub-skill runs pass**. If they fail, have it return failure, not success
- Have the reply JSON return `"work_branch": "<branch name>"` instead of `pr_number` / `pr_url` / polish fields:
  `{"issues": [<a>,<b>], "work_branch": "<name>", "worktree": "<absolute path>", "skills": [...]}`

### Integration (main thread, **always serially, one at a time**)

When an agent returns the success JSON, merge it in the main working tree (`$int_branch`):

```bash
source "$SWEEP_DIR/prelude.sh"
assert_not_base "$main_worktree"   # confirm every time that the merge target is the integration branch
git fetch origin "$work_branch"
git merge --no-ff --no-edit "$work_branch"
```

| Result | Action |
|---|---|
| Success | `git push origin "$int_branch"` → worktree cleanup → `git branch -D "$work_branch"` and `git push origin --delete "$work_branch"` → `status:"integrated"` in metrics → do not close Issues, only delete the queue line (close is in S-3) |
| Conflict | `git merge --abort` → launch the rebase agent below **only once** → re-merge |
| Re-merge also conflicts | `git merge --abort` → give up that batch. Comment on the Issue, `status:"merge_conflict"` in metrics, **delete the queue line** (leaving it makes the Stop Hook block stopping forever). Continue processing the other batches |

**Rebase agent prompt:**

```
Branch <work_branch> in worktree <worktree_path> conflicted with the integration branch <int_branch>.

1. `cd <worktree_path> && git fetch origin && git rebase origin/<int_branch>`
2. Resolve the conflicts. **Do not mechanically adopt one side** — resolve so that both intents are preserved
3. Make tests and lint pass
4. `git push --force-with-lease`

Reply with one line of JSON only:
{"work_branch": "<name>", "rebased": true}
{"work_branch": "<name>", "failure": "<cause in 1 line>"}
```

### CI

**Do not wait for CI green at each integration.** CI runs only once, on the final PR. There is no need to observe the result of `git push origin "$int_branch"`.

## Phase S-1': Integration for document sweeps (spec-sweep / report-sweep)

- **Do not create** a `feat/#<Issue number>` branch per item. Process all items in order on `$int_branch`
- Read the inter-item "return to the base branch" step as **stay on the integration branch** (do not checkout)
- After each item's commit, `git push origin "$int_branch"`
- Leave Issues open (designed to be handed to `/impl-en #N` later). The final PR only links Issues and does not close them

## Phase S-2: Integration polish, final PR creation, CI check

Run only once, after queue empty ∧ in-flight 0 ∧ **the spinoff-following rounds have also stopped** (see below).

### S-2-0. Integration polish (required)

Polish all diffs stacked on the integration branch **together, only once**. This is why we do not polish per work unit.
The main thread does not touch code, so delegate wholesale to the `Agent` tool (`subagent_type: develop`; follow `harness-model`).

```
Polish the diffs stacked on the integration branch <int_branch> together. Return only JSON to the main thread.

1. Create one worktree from the tip of the integration branch. **Do not checkout <int_branch> itself**
   (it fails because the main working tree holds it). Cut a dedicated branch:
   ts=$(date +%Y%m%d-%H%M%S)
   git fetch origin
   git worktree add <repo>-refine-$ts -b sweep/refine-$ts "origin/<int_branch>"
   cd <repo>-refine-$ts
2. Launch `/refine-git-en --no-merge --skip-minor --max-iter 3 --base-ref "origin/<base_branch>"` via the Skill tool.
   - `--base-ref` is the **base branch** (not the integration branch). All diffs the sweep stacked become the target
   - `--skip-minor` required: the merge gate does not look at minor. Each minor fix widens the diff and grows new minors
   - `--max-iter 3`: the integrated diff is larger than one work unit, so the usual 2 will not converge
3. If there are fix commits, push them: `git push -u origin sweep/refine-$ts`
4. One-line JSON on success:
   {"work_branch": "sweep/refine-<ts>", "worktree": "<absolute path>", "refine_status": "<clean|iter_limit|no_progress>", "refine_iters": <K>, "critical_remaining": <N>, "major_remaining": <N>, "minor_remaining": <N>, "pushed": <true|false>}
   If even launching failed: {"failure": "<cause in 1 line>", "worktree": "<absolute path if created>"}

Reply rules:
- Include nothing other than the JSON above in the final message.
- Do not create a PR (the main thread's responsibility). Nobody in the sweep merges (a human does).
- If there were no fixes at all, return with `pushed: false`.
```

**Merging it in**: if `pushed: true`, use the integration procedure of S-1 as is (`git merge --no-ff` → `git push origin "$int_branch"` → worktree cleanup →
delete the work branch). The queue is empty and nothing else is in flight, so no conflict occurs.
In the unlikely event of a conflict, as in S-1: rebase agent once → give up (if given up, treat as no polish).

**Judgment**:

| Result | Action |
|---|---|
| `critical_remaining == 0 ∧ major_remaining == 0` | To S-2-1 (PR creation → CI check) |
| Either remains | Proceed to S-2-1. `sweep_notify "Manual intervention needed"`, go to S-3 with `termination_reason: "manual_intervention"`. List the remaining findings in the PR body |
| `failure` / merge abandoned | Proceed to S-2-1 as no polish, and state "統合研磨に失敗（理由）" explicitly in the PR body and report |

**Never drop a work unit.** Integrated diffs can no longer be reverted, so if critical/major remain, the only gate is
to state the remaining findings explicitly in the PR body and report and defer to human judgment. **The sweep never merges the final PR anyway** (S-2-2),
so even with remaining findings, do not stop; proceed to S-2-1 and prioritize leaving a record.

### S-2-1. Create the PR (**do not merge**)

```bash
source "$SWEEP_DIR/prelude.sh"
git push origin "$int_branch"
gh pr create --base "$base_branch" --head "$int_branch" --title "<title>" --body-file <body>
```

- Title: `<type>: <purpose of the sweep>（#<a>, #<b>, …）`. If there are 6 or more targets, `#<a>, #<b> ほか N 件`
- Body: list the integrated work units one per line (Issue number + what was done), list those that could not be integrated as "未統合" with reasons, and the `refine-git` result summary (remaining critical/major/minor counts)
- Link all of them with `gh pr edit <PR> --add-issue <each Issue URL>`. **Do not use `Closes #N`** (closing is done explicitly in S-3)
- Record the PR number in `pr_number` of state.json
- **Do not merge this PR; return it to the user still open.** A human reviews and merges

### S-2-2. CI check (**done by the main thread. Do not delegate to an agent**)

**It is a human, not the sweep, who merges the final PR.** All that is done here is "turn CI green and hand it to a human in a mergeable state".

**Block and wait inside a single bash command.** If you wait by saying "Waiting." and ending the turn,
each push-back by the Stop Hook consumes one model turn:

```bash
source "$SWEEP_DIR/prelude.sh"
pr=$(jq -r '.pr_number' "$SWEEP_DIR/state.json")   # recorded in S-2-1
timeout 3600 bash -c '
  while :; do
    pending=$(gh pr view "'"$pr"'" --json statusCheckRollup \
      --jq "[.statusCheckRollup[]? | select(.conclusion == null and .status != \"COMPLETED\")] | length")
    [ "${pending:-0}" -eq 0 ] && break
    sleep 60
  done'

gh pr view "$pr" --json state,statusCheckRollup   # judge from this single result
```

When the wait ends:

- All checks complete ∧ no FAILURE ∧ `state == "OPEN"` → **do not merge**; `sweep_notify "Ready to merge" "PR #<PR>: CI 緑。レビューしてマージしてください" ":white_check_mark:"` and go to S-3. Do not run `gh pr merge`
- FAILURE present ∧ pending 0 → launch the CI fix agent **passing the failed check names** (fix and push in the `$int_branch` worktree). **At most 2 times**
- Limit reached → leave the situation with `gh pr comment`, `sweep_notify "Manual intervention needed"`, go to S-3 with `termination_reason: "manual_intervention"` (hand it back to a human with CI still red)

Use the CI fix agent prompt of normal mode as is (just swap the branch to `$int_branch`).

## Phase S-3: Issue close and report

- **Do not close Issues.** The final PR is handed to a human still open, so closing is done after the user merges.
  List the numbers in the report and PR body as "Issues to close after merge", presented in a form where the command can be pasted as is:
  `gh issue close <a> <b> --comment "Closed by PR #<PR>（single-pr sweep / integration branch: <int_branch>）"`
  Also put a `split-from:` parent Issue in the same list if all its siblings are included
- `git worktree prune`
- Always include in the Summary at the top of the report:
  ```
  - Mode: single-pr
  - Base branch: <base_branch>
  - Integration branch: <int_branch>
  - PR: <pr_url>（open — レビューとマージはユーザーが行う）
  - CI: <green（マージ可）|red（要修正）|pending>
  - Integrated: <N> / Not integrated: <M>
  ```
- In a "Not integrated" section, list the `merge_conflict` / `agent_failed` work units with reasons
- Set `phase=terminal` **after the CI result is settled** (confirmed green / CI fix reached its limit). Do not terminalize merely because the PR was opened

## Relationship with spinoff following

In normal mode PRs increase per round, but in single-pr mode **spinoff rounds are also stacked on the same integration branch**.

- Run spinoff detection **before S-2**
- If there is a round to follow → write a new queue and return to phase 2 (= S-1). Reuse the integration branch as is
- Proceed to S-2 after the rounds have stopped

## Forbidden actions (common to single-pr mode)

- **Skipping P-0 and entering S-0** (the integration branch would be cut with the base unconfirmed. See `branch-preflight.md`)
- **Creating a PR per work unit** (`gh pr create` is run by the main thread exactly once, in S-2)
- **Proceeding with the integration branch only locally, without pushing** (a crash wipes all results. Push in S-0-2 and after each integration)
- **Running integration merges in parallel** (they share the one main working tree. Merging is always serial)
- **Waiting for CI green at every integration** (erases the whole benefit of this mode. CI runs once, on the final PR)
- **Launching `/refine-git-en` per work unit** (would detect and fix the same findings as many times as there are work units. Polish is once, in S-2-0)
- **Skipping the integration polish of S-2-0 and submitting the final PR** (in single-pr mode this is the only review gate)
- **Passing the integration branch as `--base-ref` of the integration polish** (the diff becomes empty and `refine-git` fails with exit 2. Pass `origin/$base_branch`)
- **Running the integration polish directly in the main working tree** (it holds `$int_branch`, so worktree creation fails. Delegate to an agent that cuts a dedicated branch)
- **Moving on while leaving a conflicted batch in the queue** (the Stop Hook blocks stopping forever. When giving up, always delete it and record it in metrics)
- **The sweep merging the final PR** (`gh pr merge` is never run in single-pr mode. A human always merges)
- **Setting `phase=terminal` before the CI result is settled**
- **Closing Issues while the final PR is unmerged** (closing is done after the user merges)
- **Waiting for CI by ending the turn** (use the blocking wait of S-2-2. One round trip with the Stop Hook = one model turn)
- **Closing Issues via `Closes #N` in the PR body** (unify on the explicit close of S-3)
- **Trying to carry `$int_branch` / `$base_branch` by passing shell variables around** (Bash is a new shell every time. Write them to state.json in S-0-3, and read via `source "$SWEEP_DIR/prelude.sh"` afterward)
- Changing the base branch / integration branch midway
