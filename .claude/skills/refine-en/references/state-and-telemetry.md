# refine family: State Management and Telemetry

Spec for `.sweep/state.json` and `.sweep/refine-metrics.jsonl`, shared by `refine-en` / `refine-git-en`.

## `.sweep/state.json`

Progress-state file common to the sweep family of skills. **The location is always `$SWEEP_DIR` (the main-repository side; see step 3 of `common-setup.md`)**. The Stop Hook (`check-sweep-state.sh`) blocks stopping while `phase != "terminal"` (as long as the lock is fresh). **Never set `phase=terminal` by estimation without confirming the final iteration's review result.**

When `OWNS_STATE=false` (the calling sweep owns state.json), skip every write to this file and only append telemetry (guard in step 4 of `common-setup.md`).

**Schema:**
```json
{
  "skill": "refine" | "refine-git",
  "started_at": "<ISO8601>",
  "updated_at": "<ISO8601>",
  "phase": "iterating" | "terminal",
  "iteration": <N>,
  "max_iter": <N>,
  "thresholds": {"critical": 0, "major": 0, "minor": <max_minor>},
  "last_counts": {"critical": <N>, "major": <N>, "minor": <N>},
  "termination_reason": null | "thresholds_met" | "iter_limit" | "no_progress" | "agent_failed" | "merge_failed" | "ci_gave_up" | "atomic_design_required" | "aborted",
  "pr_number": <N>
}
```

**Update timing:**
- At the start of Phase 1, initialize with `phase=iterating, iteration=0` (see `common-setup.md`)
- At the end of each iteration (right after the telemetry append), do `iteration += 1`, overwrite `last_counts` with the latest review tally, and update `updated_at`. `last_counts` is used for the `no_progress` decision in 2-3, so always update it
- In Phase 3, set `phase=terminal` and `termination_reason`

**The audit trail is consolidated into `$SWEEP_DIR/refine-metrics.jsonl` alone.** The `evidence` array in state.json that mirrored line numbers has been removed (the Stop Hook does not use it for decisions; it only held the same information in 3 places).

## Per-iteration telemetry append + state.json update

```bash
# Telemetry append (file shared by refine / refine-git; distinguished by source)
jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg skill "$skill_name" \
  --argjson pr "$pr_number" \
  --argjson iter "$iter" \
  --argjson c "$(echo "$findings" | jq '.critical | length')" \
  --argjson m "$(echo "$findings" | jq '.major | length')" \
  --argjson mn "$(echo "$findings" | jq '.minor | length')" \
  --argjson by_src "$(echo "$findings" | jq '.by_source')" \
  --argjson halt "$HAS_HALT" \
  '{ts:$ts,source:$skill,pr_number:$pr,iter:$iter,critical:$c,major:$m,minor:$mn,by_source:$by_src,halt:$halt}' \
  >> "$SWEEP_DIR/refine-metrics.jsonl"

# Update state.json (only when OWNS_STATE=true)
[[ "$OWNS_STATE" == "true" ]] && jq --argjson iter "$iter" \
   --argjson c "$(echo "$findings" | jq '.critical | length')" \
   --argjson m "$(echo "$findings" | jq '.major | length')" \
   --argjson mn "$(echo "$findings" | jq '.minor | length')" \
   --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
   '.iteration = $iter
    | .last_counts = {critical:$c, major:$m, minor:$mn}
    | .updated_at = $now' \
   "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
```

## Notes for consumers

`$SWEEP_DIR/refine-metrics.jsonl` is written by both `refine-en` and `refine-git-en` (`source` = `refine` / `refine-git`). Code that aggregates the lines (e.g. report generation in `issue-sweep-en`) MUST distinguish them by `source`:

```bash
# Take only the refine-family lines
jq 'select(.source | startswith("refine"))' "$SWEEP_DIR/refine-metrics.jsonl"

# Exclude the refine-family lines
jq 'select(.source | startswith("refine") | not)' "$SWEEP_DIR/refine-metrics.jsonl"
```

**`$SWEEP_DIR` points to the main repository even when running inside a worktree**, so deleting the worktree no longer deletes the telemetry (it used to, which left the refine section of the `issue-sweep-en` report always empty).
