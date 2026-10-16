# refine family: Common Setup (Phase 1)

Initialization steps shared by `refine-en` / `refine-git-en`. The calling SKILL.md sets `skill_name` beforehand (`refine` or `refine-git`).

## 1. Identify the target

1. Argument is a PR number: `gh pr view <n> --json number,headRefName,baseRefName,url`
2. No argument: try `gh pr view --json ...` on the current branch. If there is none, target the current branch directly

Keep `pr_number` / `branch` (headRefName) / `base_branch` (baseRefName) from the result in variables. If there is no PR, leave `base_branch` empty.

## 2. Acquire a worktree (mandatory)

To protect the main worktree, acquire a worktree in one of the following ways:

- **Already launched inside a worktree** (e.g. the engineer agent of issue-sweep-en, a call from `impl-wt-r-en`): compare `git rev-parse --show-toplevel` with `git worktree list --porcelain`; if the current directory is a worktree, **reuse it** (do not create a new one)
- **Launched in the main worktree** (e.g. the user runs `/refine-git-en #42` directly): create a new worktree for the PR branch following `references/worktree-setup.md` in `impl-wt-en`. Run every Phase 2/3 operation inside the worktree from then on

## 3. Initialize variables

```bash
start_ts=$(date +%s)
iter=0
max_minor=5      # overridden by --max-minor
max_iter=10      # overridden by --max-iter
skip_minor=false # true with --skip-minor (refine-git-en only; always true from issue-sweep-en)

# `.sweep/` **always points to the main repository side**. Do not let it split even when running inside a worktree
# (deleting the worktree would delete the telemetry, and the Stop Hook would end up looking at a different file)
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
mkdir -p "$SWEEP_DIR"
```

From here on, every `.sweep/...` means `$SWEEP_DIR/...`.

## 4. Initialize `.sweep/state.json` (**ownership guard required**)

`.sweep/` is shared by the main repository, so when called from `issue-sweep-en` the **sweep owns state.json**. Overwriting it breaks the sweep's progress state (`queue_remaining`, etc.), and the moment Phase 3 sets `phase=terminal`, **the Stop Hook block is released and the sweep quietly ends mid-queue**.

```bash
# If the existing state.json belongs to another skill and is not yet terminal → the sweep owns it. Do not touch
owner=$(jq -r '.skill // ""' "$SWEEP_DIR/state.json" 2>/dev/null)
owner_phase=$(jq -r '.phase // ""' "$SWEEP_DIR/state.json" 2>/dev/null)
if [[ -n "$owner" && "$owner" != "$skill_name" && "$owner_phase" != "terminal" ]]; then
  OWNS_STATE=false   # never write state.json (write telemetry only)
else
  OWNS_STATE=true
fi
```

When `OWNS_STATE=false`, skip all of the initialization, updates, and terminal-marking below, and only append to `$SWEEP_DIR/refine-metrics.jsonl`. The calling sweep holds stop control, so no Stop Hook countermeasure is needed.

Only when `OWNS_STATE=true`:

```bash
jq -n --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
      --arg skill "$skill_name" \
      --argjson mi "$max_iter" --argjson mm "$max_minor" \
      --argjson pr "${pr_number:-null}" '{
  skill: $skill,
  started_at: $now, updated_at: $now,
  phase: "iterating", iteration: 0, max_iter: $mi,
  thresholds: {critical: 0, major: 0, minor: $mm},
  last_counts: {critical: null, major: null, minor: null},
  termination_reason: null,
  pr_number: $pr
}' > "$SWEEP_DIR/state.json"
```

For the schema and update rules in detail, see `state-and-telemetry.md`.

## 5. HALT project detection (first time only, keep the result in a variable)

```bash
HAS_HALT=false
if find . -name "*.templ" -not -path "./node_modules/*" -not -path "./.git/*" 2>/dev/null | grep -q .; then
  HAS_HALT=true
elif grep -rli "HALT\|HTMX+Atomic+Lit+Templ" docs/ SPEC.md README.md 2>/dev/null | grep -q .; then
  HAS_HALT=true
fi
```

## 6. Atomic Design project detection

Decide only when not HALT (exclusive, because `halt-review` includes Atomic).

```bash
HAS_ATOMIC=false
if [[ "$HAS_HALT" != "true" ]]; then
  for base in components src/components app/components; do
    if [[ -d "$base/atoms" ]] && { [[ -d "$base/molecules" ]] || [[ -d "$base/organisms" ]]; }; then
      HAS_ATOMIC=true
      break
    fi
  done
fi
```

## 7. Mandatory Atomic Design guard for frontend projects

```bash
IS_FRONTEND=false
if [[ -f package.json ]] && grep -qE '"(react|vue|next|nuxt)"[[:space:]]*:' package.json 2>/dev/null; then
  IS_FRONTEND=true
fi
if [[ "$IS_FRONTEND" == "true" ]] && [[ "$HAS_HALT" != "true" ]] && [[ "$HAS_ATOMIC" != "true" ]]; then
  msg="フロントエンドプロジェクト (react/vue/next/nuxt) ですが Atomic Design 構造 (atoms/molecules/organisms) が見つかりません。"
  if [[ "$OWNS_STATE" == "false" ]]; then
    # via a sweep (engineer agent of issue-sweep-en, etc.) → downgrade to a warning and continue
    echo "WARN: $msg"
    echo "  研磨と無関係な構造規約で全 Issue のマージゲートを落とさないため、警告のみで続行します。"
    echo "  atomic-review はスキップされます（HAS_ATOMIC=false）。"
  else
    echo "ERROR: $msg"
    echo "  $skill_name はフロント回りで Atomic Design 準拠を必須としています。"
    echo "  対応: components/, src/components/, app/components/ のいずれかに atoms/ + (molecules/ or organisms/) を配置してください。"
    jq --arg reason "atomic_design_required" --arg now "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       '.termination_reason = $reason | .phase = "terminal" | .updated_at = $now' \
       "$SWEEP_DIR/state.json" > "$SWEEP_DIR/state.json.tmp" && mv "$SWEEP_DIR/state.json.tmp" "$SWEEP_DIR/state.json"
    exit 2
  fi
fi
```

**When the user runs `/refine-git-en` directly (`OWNS_STATE=true`), it stops as before.** Stopping is for "telling a human about the convention violation", not for wiping out a running autonomous sweep.
