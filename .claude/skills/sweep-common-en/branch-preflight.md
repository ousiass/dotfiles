# Branch pre-guard (shared by sweep family)

Spec for **phase P-0** (confirm mode and base branch) and the **pre-guard** (preventing direct commits to the base branch), shared by `issue-sweep-en` / `refine-sweep-en` / `spec-sweep` / `report-sweep`. The calling SKILL.md sets `skill_name` beforehand.

Two accidents are prevented:

- Committing directly to the base branch (`develop` / `main`)
- Adopting the current HEAD as the base branch by guessing, without confirming with the user

## Premise: shell variables do not survive until the next Bash call

The Bash tool starts a **new shell per call**; neither env vars nor functions carry over (only cwd persists).
If you assume `$base_branch` / `$int_branch` / `assert_not_base` are "usable from now on since I defined them once",
from the second call on they become an **empty string and an undefined function**, and the guard passes silently.

**state.json is the only carrier.** Re-read variables from it every time.

### P-0-0. Generate the prelude (once, at the very start of P-0)

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
mkdir -p "$SWEEP_DIR"
cat > "$SWEEP_DIR/prelude.sh" <<'PRELUDE'
# Sweep-common prelude. Source it at the top of every bash call.
set -uo pipefail
_sw_get() { [[ -f "$SWEEP_DIR/state.json" ]] && jq -r --arg k "$1" '.[$k] // empty' "$SWEEP_DIR/state.json" 2>/dev/null || true; }
base_branch=$(_sw_get base_branch)
int_branch=$(_sw_get int_branch)
main_worktree=$(git rev-parse --show-toplevel)
PROTECTED_BRANCHES="main master develop staging production"

# $1: path of the working tree to check
assert_not_base() {
  local dir="$1" cur
  cur=$(git -C "$dir" rev-parse --abbrev-ref HEAD)
  if [[ -z "$base_branch" ]]; then
    echo "ERROR: base_branch が未確定（P-0 未実行 / state.json 欠損）" >&2
    return 1
  fi
  if [[ "$cur" == "$base_branch" || " $PROTECTED_BRANCHES " == *" $cur "* ]]; then
    echo "ERROR: $dir が保護ブランチ $cur に居ます。作業ブランチを作ってから続行してください" >&2
    return 1
  fi
  # In single-pr mode the main working tree must not be on anything but the integration branch
  if [[ -n "$int_branch" && "$dir" == "$main_worktree" && "$cur" != "$int_branch" ]]; then
    echo "ERROR: メイン作業ツリーが $cur に居ます（期待: $int_branch）" >&2
    return 1
  fi
}
PRELUDE
```

### At the top of every bash call (everything after P-0-0)

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
source "$SWEEP_DIR/prelude.sh"
```

**The bash snippets in this file and in each SKILL.md are all written assuming these 2 lines are at the top.**
Never omit the 2 lines from a snippet that references `$base_branch` / `$int_branch` / `$main_worktree` / `assert_not_base`.

## Phase P-0: Confirm mode and base branch (required, cannot be skipped)

Run **right after** lock acquisition (phase 0) and **before** queue construction / review execution (phase 1).
**Run P-0-0 (prelude generation) first**, then enter P-0-1.
P-0-2 may be skipped **only when both `--single-pr` / `--multi-pr` and `--base` are fixed by arguments**.

### P-0-1. Gather candidates

```bash
source "$SWEEP_DIR/prelude.sh"
git fetch origin --prune
git branch -r --format='%(refname:short)' | sed 's|^origin/||' | grep -v '^HEAD$'
cur_branch=$(git rev-parse --abbrev-ref HEAD)
```

### P-0-2. Ask 2 questions together with `AskUserQuestion` (once only)

The question text, headers, and options below are shown to the user, so they stay in Japanese:

| 質問 | header | 選択肢 |
|---|---|---|
| この sweep の PR の出し方 | `PR モード` | **1 PR に集約（推奨）**: 統合ブランチ `sweep/<skill_name>-<ts>` に全作業を積み、最後にベースへ PR を 1 本だけ出す。複数 Issue の実装をまとめてレビューできる。**この PR は自動マージされず open のまま返る**（レビューとマージはユーザー） ／ **作業単位ごとに PR**: バッチ・Issue ごとに PR を作る。1 本あたりは小さいが本数が増え、横断レビューはできない |
| ベースブランチ（PR のマージ先） | `ベース` | P-0-1 の remote 一覧から `develop` / `main` / `$cur_branch` を優先して 3 つ提示。それ以外は「Other」の自由入力 |

**Never adopt the current branch or `develop` by guessing.** The user decides the starting point.

```bash
git rev-parse --verify "origin/$base_branch" >/dev/null 2>&1 \
  || { echo "ERROR: origin/$base_branch が存在しません" >&2; exit 2; }
```

### P-0-3. Keep the decision in state.json

```json
{ "mode": "single-pr" | "multi-pr", "base_branch": "<base>" }
```

If state.json already exists, update it with `jq`. **For skills that have not yet created state.json at this point (issue-sweep initializes it at the end of queue construction), always include these two at that initialization.**
Take care that a later initialization does not overwrite the whole state.json and erase P-0's decisions.

`mode` is the sole basis for later phase branching. Do not re-read whether arguments were given.

### P-0-4. Continuation per mode

- `single-pr` → proceed to **S-0-2** of `single-branch-mode.md` (the base confirmation of S-0-1 is already done here)
- `multi-pr` → to phase 1 of normal mode. Leave the main working tree on `$base_branch`

### P-0-5. Confirm the main working tree is clean

```bash
source "$SWEEP_DIR/prelude.sh"
[[ -z "$(git -C "$main_worktree" status --porcelain)" ]] \
  || { echo "ERROR: メイン作業ツリーに未コミットの変更があります。退避してから再実行してください" >&2; exit 2; }
```

## Pre-guard

**No after-the-fact detection or automatic evacuation.** Always stop **before** creating a dangerous state.

The definition of `assert_not_base` is in the prelude above. Callers only need to source the prelude and
**must not copy the function definition into each snippet** (if the definition splits into two, only one gets fixed by accident).

```bash
SWEEP_DIR="${CLAUDE_PROJECT_DIR:-$(dirname "$(git rev-parse --path-format=absolute --git-common-dir)")}/.sweep"
source "$SWEEP_DIR/prelude.sh"
if ! assert_not_base "$main_worktree"; then
  # Give up this work unit (status:"branch_guard" in metrics, delete the queue line, go next)
  exit 2
fi
```

On `return 1`, **give up that work unit**, leave `status:"branch_guard"` in metrics, delete the queue line, and move on.
Do not try to fix it automatically with `git reset` / `git checkout -f` etc.

### Call sites

| Caller | Timing | Call |
|---|---|---|
| Main thread (common) | Start of P-0 | Generate the prelude in P-0-0 |
| Main thread (common) | Right after P-0 | Cleanliness check of P-0-5 |
| Main thread (common) | Top of **every** bash call that uses `$base_branch` / `assert_not_base` | `source "$SWEEP_DIR/prelude.sh"` |
| Main thread (single-pr) | Right after creating the integration branch in S-0-2 | `assert_not_base "$main_worktree"` |
| Main thread (single-pr) | Right before the integration `git merge` / `git push` in S-1 | `assert_not_base "$main_worktree"` |
| Main thread (multi-pr of spec-sweep / report-sweep) | Right after creating the `feat/#N` branch, before running spec-gen | `assert_not_base "$main_worktree"` |
| Implementation agent (issue-sweep-en / refine-sweep-en) | Right after worktree creation, and before the first `git commit` | **Always embed the snippet below in the prompt** |

### Snippet to embed in the implementation agent prompt

```
0. Always run before starting work:
   cd <worktree_path>
   cur=$(git rev-parse --abbrev-ref HEAD)
   [[ "$cur" != "<base_branch>" && "$cur" != "main" && "$cur" != "develop" ]] || exit 2

   If worktree creation fails, **do not work in the main repository instead**.
   Return {"...": ..., "failure": "worktree creation failed"} and exit immediately.
   Run the same verification once more before the first commit.
```

## Forbidden actions

- **Skipping P-0 and entering phase 1** (the worktree's branch origin gets decided with the base unconfirmed)
- **Adopting the current HEAD / `develop` / `main` without asking for the base branch**
- **Doing substitute work in the main repository when worktree creation fails** (the main cause of direct commits)
- **Automatically "fixing" a state caught by the guard with `git reset` / `git checkout -f` / `git stash` and continuing** (policy is pre-guard only. Hand it back to a human)
- **Judging `mode` from arguments each time without writing it to state.json** (interpretation drifts between phases)
- **Assuming shell variables / functions survive until the next Bash call** (the Bash tool is a new shell every time. `$base_branch` becomes an empty string and `assert_not_base` becomes undefined, so the guard passes silently. Source the prelude every time)
- **Copying the definition of `assert_not_base` into snippets** (it is defined in exactly one place, the prelude)
