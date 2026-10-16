# refine family: Merge, Report, and Termination (Phase 3)

Termination flow shared by `refine-en` / `refine-git-en`. `skill_name` / `pr_number` / `branch` / `iter` / `findings` / `start_ts` are assumed to be set by the caller.

## 1. Fix the elapsed time and status

```bash
total_dur=$(( $(date +%s) - start_ts ))
```

Pick status from the enum below. **Do not invent other strings (e.g. `stuck`)** — the calling `issue-sweep-en` parses it:

- Threshold reached → `clean` (proceed to merge)
- `max_iter` reached → `iter_limit` (do not merge)
- `critical + major` not dropping for 2 consecutive iterations → `no_progress` (do not merge)
- Agent failure → `agent_failed` (do not merge)
- Merge itself failed → `merge_failed` / gave up on CI fixes → `ci_gave_up`

## 2. Wait for CI green, merge directly → close Issue

Run only when status=`clean` and `--no-merge` was not given. With `--no-merge`, skip this step entirely and go to 3.

```bash
sweep_notify "$skill_name: waiting for CI green" "PR #${pr_number}" ":hourglass:"

# statusCheckRollup polling
respawn=0
while true; do
  payload=$(gh pr view "$pr_number" --json state,mergedAt,statusCheckRollup)
  state=$(echo "$payload" | jq -r .state)
  merged=$(echo "$payload" | jq -r '.mergedAt // "null"')
  failed=$(echo "$payload" | jq -r '[.statusCheckRollup[]? | select(.conclusion == "FAILURE") | .name] | join(",")')
  pending=$(echo "$payload" | jq '[.statusCheckRollup[]? | select(.conclusion == null and .status != "COMPLETED")] | length')

  [[ "$state" == "MERGED" ]] && break

  if [[ "$state" == "CLOSED" && "$merged" == "null" ]]; then
    status="merge_failed"; break
  fi

  if [[ -n "$failed" && "$pending" -eq 0 ]]; then
    if (( respawn >= 2 )); then status="ci_gave_up"; merge_failure="$failed"; break; fi
    respawn=$((respawn+1))
    gh pr comment "$pr_number" --body "$skill_name: マージ前 CI 失敗を検知（attempt ${respawn}/3、checks: $failed）。修正 agent を再起動します。"
    # Launch Agent(develop) with the same fix prompt as Phase 2-4
    # For CI fixes only, allow changes outside the diff such as workflow/config files
    continue
  fi

  # All checks complete ∧ no FAILURE ∧ OPEN → merge directly
  if [[ "$pending" -eq 0 && -z "$failed" && "$state" == "OPEN" ]]; then
    if gh pr merge "$pr_number" --merge --delete-branch 2>/tmp/refine-merge-err; then
      sweep_notify "$skill_name: merged" "PR #${pr_number}" ":white_check_mark:"
      continue  # next loop breaks with state==MERGED
    else
      err=$(cat /tmp/refine-merge-err)
      status="merge_failed"; merge_failure="$err"; break
    fi
  fi

  sleep 60
done

# On merge success, close the linked Issues
if [[ "$state" == "MERGED" ]]; then
  closing_issues=$(gh pr view "$pr_number" --json closingIssuesReferences -q '.closingIssuesReferences[].number')
  for issue in $closing_issues; do
    gh issue close "$issue" --comment "Closed by PR #${pr_number} (refined and merged via /${skill_name}, iters=${iter})"
  done
fi
```

## 3. Append the final telemetry line (with status)

Append one line: the append code from `state-and-telemetry.md` plus `status`.

## 4. Fix the final counts

- **With `--no-merge` (calls from `issue-sweep-en` always use it), do not re-review.** Use the final iteration's 2-1 review result as the final counts. If not merging, "re-checking the state right before merge" is meaningless, and the caller has its own CI gate so it would be duplicated (it wasted 3–5 review-agent rounds per PR)
- **Only when merging**, before claiming status=`clean`, run the Phase 2-1 review once more and re-confirm the threshold is met (never declare clean by estimation)
- In both cases append the final counts to `$SWEEP_DIR/refine-metrics.jsonl`, and if `OWNS_STATE=true`, update `last_counts` / `updated_at` in state.json

## 5. Mark state.json terminal

**When `OWNS_STATE=false` (the calling sweep owns state.json), skip this step entirely.** Marking terminal here would release the sweep's Stop Hook block and the sweep would quietly end mid-queue.

```bash
if [[ "$OWNS_STATE" == "true" ]]; then
  reason="thresholds_met"   # or iter_limit / no_progress / agent_failed / merge_failed / ci_gave_up / aborted
  jq --arg reason "$reason" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     '.phase = "terminal" | .termination_reason = $reason | .updated_at = $now' \
     "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
fi
```

## 6. Generate the Markdown report

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
report="$SWEEP_DIR/report-${skill_name}-${ts}.md"
cat > "$report" <<EOF
# ${skill_name} report — $(date -u +%Y-%m-%dT%H:%M:%SZ)

## Target
- PR: #${pr_number}
- Branch: ${branch}
- Scope: ${scope_label}
- Iterations: ${iter}
- Final status: **${status}**
- Elapsed: ${total_dur}s

## Findings trend

| Iter | Critical | Major | Minor |
|---|---|---|---|
$(jq -r --arg skill "$skill_name" --argjson pr "$pr_number" 'select(.source == $skill and .pr_number == $pr) | "| \(.iter) | \(.critical) | \(.major) | \(.minor) |"' "$SWEEP_DIR/refine-metrics.jsonl")

## Remaining issues
$(if [[ "$status" != "clean" ]]; then echo "$findings" | jq -r '.critical[]?, .major[]?, .minor[]? | "- [\(.file // "?"):\(.line // 0)] \(.msg)"'; else echo "なし（閾値到達）"; fi)
EOF

echo "Report written to $report"
```

`scope_label` is set by the caller:
- `refine`: `リポジトリ全体`
- `refine-git`: `\`${base_ref}...HEAD\` の差分のみ（N files）`

After this, `refine-git-en` appends an `## Out of scope` section (see `refine-git-en/SKILL.md`).

## 7. Notification

```bash
sweep_notify "$skill_name done" "PR #${pr_number}: ${status}, ${iter} iters" "<emoji>"
```

Reuse the same `sweep_notify` function as `issue-sweep-en` (`.sweep/notify.url` is read).

## 8. Reply to the caller

Output the following single JSON line as the final message. Emit the JSON line **before** the guidance about the Markdown report path, so that the engineer agent of `issue-sweep-en` and the like can parse it.

```json
{"status":"<clean|iter_limit|no_progress|agent_failed|merge_failed|ci_gave_up>","skill":"<refine|refine-git>","pr_number":<N>,"iter":<K>,"critical_remaining":<N>,"major_remaining":<N>,"minor_remaining":<N>,"merged":<true|false>,"report_path":".sweep/report-<skill>-<ts>.md"}
```

- With `--no-merge`, `merged` is fixed at `false` (nothing was merged)
- Even for `iter_limit` / `no_progress`, when `critical_remaining=0 ∧ major_remaining=0` the caller can judge "OK with only minor leftovers" (the `issue-sweep-en` merge gate looks only at these two)
- Include the report path in both the final user-facing display and the JSON

## Behavior on failure

- Either the review agent or the fix agent fails → abort the loop, record `status: "agent_failed"` on the final telemetry line, generate the report and finish
- Worktree creation failed → do not start at all
- Network outage / gh error → wait 60 seconds and retry up to 3 times; if still failing, defer to the user
