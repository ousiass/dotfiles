---
name: skill-reviewer
description: 既存スキルを Anthropic 公式ガイドの 5 原則に照らして監査する。スキルのトークン効率や構成を見直したい、ベストプラクティス準拠を確認したいときに使う。Codex 標準の skill-creator を補完する評価レイヤーとして使い、本家を上書きする目的では使わない。
---

# Skill Reviewer

Anthropic の公式ガイド原則に基づき、既存スキルをレビューして改善案を提示する。

## Review Workflow

### Step 1: Read the Skill

ユーザーにスキルのパスを聞くか、`SKILL.md` の内容を貼ってもらう。

次を含めてスキル全体を読む：
- YAML frontmatter
- SKILL.md 本文
- バンドルされたリソース（scripts/, references/, templates/）

### Step 2: Analyze Against 5 Principles

各原則を評価する。詳細な採点基準は `references/evaluation-criteria.md` を参照。

#### 1. Concise is Key

Check:
- [ ] モデルが既に知っている自明な情報を削っている
- [ ] 説明よりも例を優先している
- [ ] 各記述に「このトークンコストに見合うか？」を問えている
- [ ] SKILL.md 本文が 500 行以下

**Score:** 0-10

#### 2. Progressive Disclosure

Check:
- [ ] YAML description は 100 文字程度以下で、適切に発火する
- [ ] SKILL.md 本文は関連時のみ読み込まれる粒度になっている
- [ ] 詳細は適宜 references/ に逃がしている
- [ ] reference ファイルへの導線が明確

**Score:** 0-10

#### 3. Degrees of Freedom

Check:
- [ ] 各ステップに適切な自由度が設定されている
- [ ] High freedom: 複数の妥当なアプローチを許容
- [ ] Medium freedom: 推奨パターン＋バリエーション
- [ ] Low freedom: 壊れやすい操作には厳密なスクリプト

**Score:** 0-10

#### 4. Composability

Check:
- [ ] 他のスキルと併用しても破綻しない
- [ ] リソースの排他的利用を前提にしない
- [ ] ハードコードされたパスやグローバル状態がない
- [ ] 必要であれば変数名を namespace する

**Score:** 0-10

#### 5. Portability

Check:
- [ ] Codex CLI、Claude.ai、Claude Code、API のいずれでも動く
- [ ] 環境依存を明示している
- [ ] SKILL.md 内にプラットフォーム固有コードを書かない
- [ ] 必要に応じて代替手段を提示

**Score:** 0-10

### Step 3: Calculate Metrics

**Token usage:**
```bash
# Estimate tokens
wc -w SKILL.md
# Multiply by 1.3
```

**Line count:**
```bash
wc -l SKILL.md
```

**Target:**
- YAML: < 100 chars
- Body: < 500 lines (~2500 tokens)
- Total: < 5000 tokens

### Step 4: Generate Report

Create structured report with:

```markdown
# Skill Review: [skill-name]

## Overall Score: X/50

## Principle Scores

| Principle | Score | Status |
|-----------|-------|--------|
| Concise is Key | X/10 | ⚠️/✅ |
| Progressive Disclosure | X/10 | ⚠️/✅ |
| Degrees of Freedom | X/10 | ⚠️/✅ |
| Composability | X/10 | ⚠️/✅ |
| Portability | X/10 | ⚠️/✅ |

## Metrics

- YAML description: X chars (target: <100)
- SKILL.md lines: X (target: <500)
- Estimated tokens: X (target: <2500)
- Total skill tokens: X (target: <5000)

## Issues Found

### Critical (Must Fix)
1. [Issue description]
   - Current: [example]
   - Problem: [why it's bad]
   - Fix: [specific solution]

### Important (Should Fix)
2. [Issue description]
   - Current: [example]
   - Problem: [why it's bad]
   - Fix: [specific solution]

### Minor (Nice to Have)
3. [Issue description]
   - Current: [example]
   - Improvement: [suggestion]

## Strengths

- [What the skill does well]
- [Good patterns to keep]

## Recommendations

### Quick Wins (< 30 min)
1. [Specific actionable change]
2. [Specific actionable change]

### Medium Effort (1-2 hours)
1. [Restructuring suggestion]
2. [Content reorganization]

### Major Refactor (> 2 hours)
1. [Significant changes]
2. [Architecture improvements]

## Example Improvements

[Show before/after for 2-3 key issues]
```

### Step 5: Offer to Generate Improved Version

ユーザーに「改善版を作りますか？」と聞く。

Yes の場合：
1. 推奨に従って改善版 SKILL.md を作成
2. 必要なら progressive disclosure に沿って再構成
3. 冗長な部分を references/ に逃がす
4. 不足リソースを追加
5. 基準に照らして検証
6. 改善版を提示

## Common Issues

詳細な事例は `references/common-issues.md` を参照：

**Token Efficiency:**
- 冗長な説明
- 自明な情報
- 重複コンテンツ

**Structure:**
- progressive disclosure 不在
- 全部が SKILL.md に押し込まれている
- ナビゲーションが貧弱

**Clarity:**
- 曖昧な指示
- 例が足りない
- 自由度が不明瞭

**Compatibility:**
- ハードコードされたパス
- プラットフォーム固有コード
- 環境依存が未記載

## Quick Check Mode

時間がない場合、まず Top 5 をチェック：

1. **YAML description が 100 文字超？** → 短くする
2. **SKILL.md が 500 行超？** → references/ に分割
3. **「Claude は…」「You should…」が多い？** → 削る
4. **例が皆無で散文ばかり？** → 例を追加
5. **全部が 1 ファイル？** → progressive disclosure を導入

## Scoring Guide

**40-50:** Excellent - 全原則を満たす
**30-39:** Good - 軽微な改善
**20-29:** Fair - 大幅な改善が必要
**10-19:** Poor - 大規模リファクタが必要
**0-9:** Critical - 全面書き直し推奨

## Output Format

常に次を提示する：
1. 構造化されたレビューレポート
2. 具体的でアクション可能な推奨
3. 主要な指摘の Before/After 例
4. 改善版を生成する申し出

建設的かつ具体的に。インパクトの高い改善を優先する。
