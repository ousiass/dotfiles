# sweep-common-en

> Source of truth: the Japanese `sweep-common` is canonical. This `-en` directory is a translation; update it after the Japanese version changes.

Specs shared by `issue-sweep-en` / `refine-sweep-en` / `spec-sweep` / `report-sweep`. **Not launched on its own** (it has no `SKILL.md`, so it does not appear as a skill).

| File | Content | When to read |
|---|---|---|
| `branch-preflight.md` | Prelude generation (P-0-0), phase P-0 (confirm mode and base branch), pre-guard `assert_not_base` | **Every sweep always reads it at startup** |
| `single-branch-mode.md` | Mode that consolidates into 1 integration branch → 1 PR (S-0 to S-3) | Only with `--single-pr` |
| `notifications.md` | Implementation of `sweep_notify` and notification timing | Only when `$SWEEP_DIR/notify.url` exists |

The calling SKILL.md must set `skill_name` before reading. Write references as relative paths `../sweep-common-en/<file>` (do not hard-code assuming `~/.claude`, so it does not break when placed in a project-bundled `.claude/skills/`).
