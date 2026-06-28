---
name: skill-creator
description: Anthropic 公式 33 ページガイドに基づく拡張スキル作成ガイドライン。新しいスキルを設計・記述する際、プログレッシブディスクロージャーやトークン効率などのベストプラクティスを参照したいときに使う。Codex 標準の skill-creator（`~/.codex/skills/.system/skill-creator`）を上書きするものではなく、補助的な知識層として併用する。
---

# Skill Creator Max

## Core Principles (from Official Guide)

### 1. Concise is Key

**Default assumption: モデルは既に十分に賢い。** モデルが持っていない文脈のみを追加する。

各記述を「このトークンコストに見合うか？」と問い直す。

説明よりも例を優先する。

### 2. Progressive Disclosure

Three-level system:
- **Level 1 (YAML)**: Always loaded (~30-50 tokens) - when to use the skill
- **Level 2 (Body)**: Loaded when relevant (<500 lines) - how to use it
- **Level 3 (Files)**: Discovered as needed - detailed references

### 3. Degrees of Freedom

- **High**: Text instructions (multiple valid approaches)
- **Medium**: Pseudocode (preferred pattern with variation)
- **Low**: Exact scripts (fragile operations)

Analogy: Narrow bridge needs guardrails (low), open field allows many routes (high).

### 4. Composability

他のスキルと共存できるように書く。リソースを独占する前提を置かない。

### 5. Portability

Codex CLI、Claude.ai、Claude Code、API といった異なるハーネス上で同じ挙動になるように設計する。ハーネス固有のツール名や前提に依存しすぎないこと。

## Skill Creation Workflow

### Step 1: Understand with Examples

ユーザーに次を確認する：
- 「このスキルでどんなタスクを扱いたいか？」
- 「具体的な使用例を 2〜3 個ほしい」
- 「何が共通で、何が変わるか？」

機能の輪郭がはっきりしたら次へ。

### Step 2: Determine Category

**Category 1: Standalone workflow**
- 外部ツール不要
- 例: ドキュメント整形、コードレビューのチェックリスト

**Category 2: Tool integration**
- 特定のファイル形式や API を扱う
- 例: PDF 処理、API 連携パターン

**Category 3: MCP-enhanced**
- 既存の MCP サーバーと協調する
- 例: データベース運用、外部サービス連携

### Step 3: Plan Resources

バンドルするものを洗い出す：

| Resource | When to Use | Example |
|----------|-------------|---------|
| `scripts/` | 繰り返し書き直されるコード | `rotate_pdf.py` |
| `templates/` | 毎回同じ雛形を出す場合 | HTML スターター |
| `references/` | 必要時に参照する詳細ドキュメント | API スキーマ |

### Step 4: Design YAML

**Good:**
```yaml
description: Generate React components from Figma specs using Tailwind CSS
```

**Bad:**
```yaml
description: This skill helps you create React components. It will analyze your Figma designs and generate corresponding React code using Tailwind CSS for styling. The components will be responsive and follow best practices.
```

First is 65 chars, second is 213 chars. First gives enough info for relevance matching.

**Formula:** What it does + When to use it (under 100 chars)

### Step 5: Structure the Body

**Template:**

1. Brief overview (1-2 paragraphs)
2. Core workflow (numbered steps or sections)
3. Examples (concise, demonstrative)
4. Edge cases (if critical)
5. References to bundled resources (if any)

**Keep under 500 lines.**

### Step 6: Set Degrees of Freedom

For each workflow step, ask:
- How fragile is this operation?
- How much variation is acceptable?
- Does context affect the approach?

**Example - High freedom:**
```markdown
Analyze requirements and propose database schema. Consider normalization and query patterns.
```

**Example - Medium freedom:**
```markdown
1. Parse input specification
2. For each entity: define primary key, list attributes, identify relationships
3. Generate CREATE TABLE statements
```

**Example - Low freedom:**
```bash
#!/bin/bash
# Use this exact script
psql -U $DB_USER -d $DB_NAME -f schema.sql
```

### Step 7: Write SKILL.md

命令形で簡潔に書く。

**Frontmatter:**
- `name`: skill-name (lowercase with hyphens)
- `description`: What it does + when to use it (<100 chars 目安)

**Body:**
- 「なぜ」よりも「何をするか」から始める
- 説明より例を優先する
- バンドルファイルは明示的に参照する
- 500 行以下に収める

### Step 8: Create Bundled Resources

**scripts/**: 実行可能コード
- shebang を入れる
- パラメータをコメントで説明する
- 含める前にテストする

**references/**: ドキュメント
- 必要時のみ読み込まれる
- API ドキュメント、スキーマ、サンプル
- 大きなファイル（>10k words）は SKILL.md に grep パターンを書いておく

**templates/**: 静的ファイル
- コンテキストには読み込まれない
- HTML テンプレート、設定ファイル、アセット

**Avoid duplication:** 情報は SKILL.md か references のどちらか一方に置く。両方に書かない。

### Step 9: Validate

Check:
- [ ] YAML description が要点を伝えているか（<100 chars 目安）
- [ ] Body が 500 行以下か
- [ ] 説明よりも例を優先しているか
- [ ] モデルが既に知っている自明な情報を含めていないか
- [ ] 各 reference ファイルをいつ読むべきか明確か
- [ ] スクリプトがテスト済みで動作するか

### Step 10: Deliver

パッケージ化してユーザーに渡し、テストしてもらう。

## Common Patterns

詳細な例は `references/patterns.md` を参照：
- ドキュメント処理ワークフロー
- コード生成パターン
- API 連携パターン
- MCP 連携ワークフロー

## Advanced Topics

詳細は `references/advanced.md` を参照：
- トークン最適化戦略
- マルチドメインスキルの構成
- 条件分岐ワークフロー
- テストと反復

## Kitchen Analogy

**MCP = Professional kitchen** (tools, ingredients, equipment)

**Skills = Recipes** (step-by-step instructions)

**Model = Chef** (knows general principles, follows recipes for consistency)

MCP サーバーが稼働しているなら、Skills はその上にのる知識層という位置づけ。

## Quick Reference

**Token budget:**
- YAML: <100 chars 目安
- Body: <500 lines (~2500 tokens)
- Total skill: <5000 tokens

**File structure:**
```
skill-name/
├── SKILL.md (required)
├── scripts/ (optional)
├── references/ (optional)
└── templates/ (optional)
```

**Don't include:** README.md, CHANGELOG.md, LICENSE（スキルは AI のためのもので、人間向け配布物ではない）

## Let's Build

スキルを作る準備ができたら、まず次に答えてもらう：

**このスキルでどんなタスクやワークフローを扱いたいか？**

具体的な使い方を 2〜3 個挙げてもらう。
