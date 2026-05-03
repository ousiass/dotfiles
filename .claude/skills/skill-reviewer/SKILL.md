---
name: skill-reviewer
description: Review existing skills against Anthropic's official guide principles. Use for: auditing skills, improving token efficiency, ensuring best practices compliance.
---

# Skill Reviewer

Review and improve existing skills based on Anthropic's official guide principles.

## Review Workflow

### Step 1: Read the Skill

Ask user for skill path or have them paste SKILL.md content.

Read the entire skill including:
- YAML frontmatter
- SKILL.md body
- Any bundled resources (scripts/, references/, templates/)

### Step 2: Analyze Against 5 Principles

Evaluate each principle. See `references/evaluation-criteria.md` for detailed scoring.

#### 1. Concise is Key

Check:
- [ ] Removes obvious information Claude already knows
- [ ] Prefers examples over explanations
- [ ] Challenges each piece: "Does this justify token cost?"
- [ ] SKILL.md body < 500 lines

**Score:** 0-10

#### 2. Progressive Disclosure

Check:
- [ ] YAML description < 100 chars, triggers appropriately
- [ ] SKILL.md body loaded when relevant
- [ ] Details moved to references/ when appropriate
- [ ] Clear navigation to reference files

**Score:** 0-10

#### 3. Degrees of Freedom

Check:
- [ ] Appropriate freedom level for each step
- [ ] High freedom: Multiple valid approaches
- [ ] Medium freedom: Preferred patterns with variation
- [ ] Low freedom: Exact scripts for fragile operations

**Score:** 0-10

#### 4. Composability

Check:
- [ ] Works alongside other skills
- [ ] No exclusive resource assumptions
- [ ] No hardcoded paths or global state
- [ ] Namespaced variables if needed

**Score:** 0-10

#### 5. Portability

Check:
- [ ] Works on Claude.ai, Claude Code, API
- [ ] Documents environment dependencies
- [ ] No platform-specific code in SKILL.md
- [ ] Provides fallbacks if needed

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

Ask user: "Would you like me to generate an improved version?"

If yes:
1. Create improved SKILL.md following recommendations
2. Restructure with progressive disclosure if needed
3. Move verbose content to references/
4. Add missing resources
5. Validate against criteria
6. Deliver improved version

## Common Issues

See `references/common-issues.md` for detailed examples:

**Token Efficiency:**
- Verbose explanations
- Obvious information
- Redundant content

**Structure:**
- No progressive disclosure
- Everything in SKILL.md
- Poor navigation

**Clarity:**
- Vague instructions
- Missing examples
- Unclear degrees of freedom

**Compatibility:**
- Hardcoded paths
- Platform-specific code
- Missing dependency docs

## Quick Check Mode

For fast review, check top 5 issues:

1. **YAML description > 100 chars?** → Shorten
2. **SKILL.md > 500 lines?** → Split to references
3. **Lots of "Claude is..." or "You should..."?** → Delete
4. **No examples, all prose?** → Add examples
5. **Everything in one file?** → Use progressive disclosure

## Scoring Guide

**40-50:** Excellent - Follows all principles
**30-39:** Good - Minor improvements needed
**20-29:** Fair - Significant improvements needed
**10-19:** Poor - Major refactor required
**0-9:** Critical - Complete rewrite recommended

## Output Format

Always provide:
1. Structured review report
2. Specific, actionable recommendations
3. Before/after examples for key issues
4. Offer to generate improved version

Be constructive and specific. Focus on high-impact improvements first.
