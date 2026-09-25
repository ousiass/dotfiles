---
name: harness-model
description: "omp ではサブエージェントのモデルを modelRoles が解決する。起動時に使う"
---

# harness-model

sweep / refine / impl からサブエージェントを起動するときのモデル方針。手順スキルの本文にベンダーモデル名を書かない。

## Policy

| 用途 | エージェント | モデルの決まり方 |
|---|---|---|
| 実装・修正（バッチの 1 回目） | `develop` | 定義の `model: "@task"` → `modelRoles.task` |
| 実装・修正の再試行（同一バッチの 2 回目。`agent_failed` 後の再投入のみ。`budget_exhausted` は対象外） | `develop-slow` | 定義の `model: "@slow"` → `modelRoles.slow`。難問突破用に温存している `slow` を、1 回目で収束しなかった再試行だけに絞って使う |
| レビュー | `review` | 定義の `model: "@task"` → `modelRoles.task` |
| 読み取り専用の JSON 解析 | `review` | 同上。起動側では何も渡さない |
| 安価なトリアージ（`issue-sweep` フェーズ1-2a 等の機械的な分類） | `scout` | `task.agentModelOverrides.scout: "@smol"` → `modelRoles.smol`（luna）。read-only 前提なので Issue 作成等の書き込みは行わせない |
| commit メッセージ / PR タイトルの下書き | `sonic` | `task.agentModelOverrides.sonic: "@commit"` → `modelRoles.commit`（luna）。`../sweep-common/commit-draft.md` の契約に従う |

起動側で `model` を渡さない。ロール（`@task` / `@slow`）が `~/.omp/agent/config.yml` の `modelRoles` で解決され、`task.agentModelOverrides` がエージェント単位で上書きする。モデルを変えたいときは手順スキルではなく config 側を直す。

`modelRoles.slow` は Opus 5.5（`anthropic/claude-opus-5-5:high`）。本線（`default`/`task`/`plan`/`advisor`/`vision`）は Sonnet 5 のまま（issue #30）。

### develop → develop-slow の昇格ルール（issue-sweep 専用）

- 1 回目の実装・CI fix → `develop`（`@task`）
- **同じバッチの 2 回目**（`agent_failed` 後の再投入、または CI fix の 2 回目の修正投入）→ `develop-slow`（`@slow`）
- `budget_exhausted`（`task.softRequestBudget` 超過）の再試行は昇格しない。予算切れは難易度の問題ではないので `develop` のまま resume する
- review / scout / sonic / advisor は上げない
- 「難しそう」という主観判断での自動昇格はしない。上げる基準は失敗回数（と budget_exhausted でないこと）だけ
- 具体的な判定条件は `issue-sweep` の 2-2（実装 agent 選択）/ 2-3（CI fix agent 選択）/ 2-7（試行回数の永続化）を参照

## Spawn

```
# レビュー（並列可）
task({ description: "...", agent: "review", prompt: "..." })

# 実装・修正（1 回目）
task({ description: "...", agent: "develop", prompt: "..." })

# 実装・修正の再試行（同一バッチ 2 回目、budget_exhausted 以外）
task({ description: "...", agent: "develop-slow", prompt: "..." })
```

- 起動側で `model` を渡さない
- 修正エージェント自身が develop / develop-slow。ネストして `task(agent=develop)` を呼ばない
- bundled エージェント（`scout` / `sonic` / `task` / `reviewer` / `security-reviewer`）を使う場合も同じで、割り当ては `task.agentModelOverrides` に置く

## Files

- エージェント定義: `~/.omp/agent/agents/develop.md` / `develop-slow.md` / `review.md`（`@task` / `@slow` / `@task`）
- ロール解決: `~/.omp/agent/config.yml` の `modelRoles` と `task.agentModelOverrides`
