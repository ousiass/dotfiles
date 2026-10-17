# --abort and failure recovery

**Read this file only when `--abort` is specified or processing has failed.**

## --abort handling

If the argument is `--abort`, run the following and exit (do not proceed to other phases):

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
rm -f "$SWEEP_DIR/queue.txt" "$SWEEP_DIR/lock" "$SWEEP_DIR/attempts.json"
# If state.json exists, set it to terminal (do not delete, to keep the history)
if [[ -f "$SWEEP_DIR/state.json" ]]; then
  jq --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
    '.phase = "terminal" | .termination_reason = "aborted" | .updated_at = $now' \
    "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
fi
# Clean up leftover worktrees
git worktree prune
```

When done, report "sweep を中止しキュー / ロックを削除しました" to the user.

## Behavior on failure

- **One batch's failure must not stop the whole sweep.** Give up only batches whose `attempts.json` count reached 2, delete their lines from the queue, record `agent_failed` in metrics, and keep flowing through the remaining batches
- **Always delete abandoned batches from the queue.** Leaving them makes the Stop Hook keep blocking stopping and the sweep can never finish
- On observing `CLOSED ∧ merged == false` (manual close): restart the agent the first time; defer to the user's judgment on 2 consecutive occurrences
- If the queue file is corrupted, delete everything with `--abort` and redo from phase 1
- **Even when every batch ends in give-up, proceed to the completion-report phase to terminalize and generate the report** (`termination_reason = "batch_failed"`). Ending with no record left is the worst outcome
