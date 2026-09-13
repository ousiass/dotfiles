---
name: harness-model
description: "Claude CodeではサブエージェントをOpus、Cursorでは親モデル継承。起動時に使う"
user-invocable: false
---

# harness-model

sweep / refine / impl からサブエージェントを起動するときのモデル方針。手順スキルの本文にベンダーモデル名を書かない。

## Policy

| Harness | 実装・レビュー | 読み取り専用の JSON 解析 |
|---|---|---|
| Claude Code | `develop` / `review`（`.claude/agents` の `model: opus`） | `review` + `model=sonnet` |
| Cursor | 同名エージェント。`model` パラメータは付けない | `review`。`model` は付けない |

Cursor で `subagent_type: claude` や opus / sonnet / gpt スラッグを渡すと Other Models 枠を消費する。親が Grok / Composer ならサブも親と同じ Cursor Models 枠に乗せる。

## Spawn

```
# レビュー（並列可）
Agent({ description: "...", subagent_type: "review", prompt: "..." })

# 実装・修正
Agent({ description: "...", subagent_type: "develop", prompt: "..." })
```

- `subagent_type: claude` は使わない
- Cursor では `model` を渡さない。エージェント定義の `force-default-model: true` が上書きを防ぐ
- Claude Code の解析だけ `model=sonnet` を付けて opus を上書きしてよい
- 修正エージェント自身が develop。ネストして `Agent(develop)` を呼ばない

## Files

- Claude: `.claude/agents/develop.md` / `review.md` → `model: opus`
- Cursor: `.cursor/agents/develop.md` / `review.md` → `model: inherit`
