---
name: harness-model
description: "omp ではサブエージェントのモデルを modelRoles が解決する。起動時に使う"
---

# harness-model

sweep / refine / impl からサブエージェントを起動するときのモデル方針。手順スキルの本文にベンダーモデル名を書かない。

## Policy

| 用途 | エージェント | モデルの決まり方 |
|---|---|---|
| 実装・修正 | `develop` | 定義の `model: "@task"` → `modelRoles.task` |
| レビュー | `review` | 定義の `model: "@slow"` → `modelRoles.slow` |
| 読み取り専用の JSON 解析 | `review` | 同上。起動側では何も渡さない |
| 安価なトリアージ（`issue-sweep` フェーズ1-2a 等の機械的な分類） | `scout` | `task.agentModelOverrides.scout: "@smol"` → `modelRoles.smol`（luna）。read-only 前提なので Issue 作成等の書き込みは行わせない |
| commit メッセージ / PR タイトルの下書き | `sonic` | `task.agentModelOverrides.sonic: "@commit"` → `modelRoles.commit`（luna）。`../sweep-common/commit-draft.md` の契約に従う |

起動側で `model` を渡さない。ロール（`@task` / `@slow`）が `~/.omp/agent/config.yml` の `modelRoles` で解決され、`task.agentModelOverrides` がエージェント単位で上書きする。モデルを変えたいときは手順スキルではなく config 側を直す。

## Spawn

```
# レビュー（並列可）
task({ description: "...", agent: "review", prompt: "..." })

# 実装・修正
task({ description: "...", agent: "develop", prompt: "..." })
```

- 起動側で `model` を渡さない
- 修正エージェント自身が develop。ネストして `task(agent=develop)` を呼ばない
- bundled エージェント（`scout` / `sonic` / `task` / `reviewer` / `security-reviewer`）を使う場合も同じで、割り当ては `task.agentModelOverrides` に置く

## Files

- エージェント定義: `~/.omp/agent/agents/develop.md` / `review.md`（`@task` / `@slow`）
- ロール解決: `~/.omp/agent/config.yml` の `modelRoles` と `task.agentModelOverrides`
