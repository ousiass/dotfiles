# sweep-common

`issue-sweep` / `refine-sweep` / `spec-sweep` / `report-sweep` が共有する仕様。**単体では起動しない**（`SKILL.md` を持たないので skill としては現れない）。

| ファイル | 内容 | いつ読むか |
|---|---|---|
| `branch-preflight.md` | prelude 生成（P-0-0）、フェーズ P-0（モードとベースブランチの確定）、事前ガード `assert_not_base` | **全 sweep が起動時に必ず読む** |
| `single-branch-mode.md` | 1 統合ブランチ → 1 PR に集約するモード（S-0〜S-3） | `--single-pr` のときだけ |
| `notifications.md` | `sweep_notify` の実装と通知タイミング | `$SWEEP_DIR/notify.url` が存在するときだけ |

呼び出し元 SKILL.md は事前に `skill_name` を設定してから読むこと。参照は `../sweep-common/<file>` の相対パスで書く（`~/.claude` 前提のハードコードにしない。プロジェクト同梱の `.claude/skills/` に置いても壊れないようにするため）。
