# sweep-common-en

**Source of truth: the Japanese `.claude/skills/sweep-common` (Claude Code version) is canonical; this `-en` directory is a translation of it and MUST be updated after it. It is NOT translated from the `omp/skills/` version: differences in `omp/skills/` are not reflected, so calling this `-en` in omp lacks the omp-version fixes.**

Specs shared by `issue-sweep-en` / `refine-sweep-en`. **Not launched on its own** (it has no `SKILL.md`, so it does not appear as a skill). The Japanese-only `spec-sweep` / `report-sweep` use the Japanese `sweep-common`.

| File | Content | When to read |
|---|---|---|
| `branch-preflight.md` | Prelude generation (P-0-0), phase P-0 (confirm mode and base branch), pre-guard `assert_not_base` | **Every sweep always reads it at startup** |
| `single-branch-mode.md` | Mode that consolidates into 1 integration branch → 1 PR (S-0 to S-3) | Only with `--single-pr` |
| `notifications.md` | Implementation of `sweep_notify` and notification timing | Only when `$SWEEP_DIR/notify.url` exists |

The calling SKILL.md must set `skill_name` before reading. Write references as relative paths `../sweep-common-en/<file>` (do not hard-code assuming `~/.claude`, so it does not break when placed in a project-bundled `.claude/skills/`).
