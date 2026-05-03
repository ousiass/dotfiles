# skill-reviewer

Review and improve existing skills against Anthropic's official guide principles.

## What It Does

**skill-reviewer** audits existing skills and provides:
- Scored evaluation (0-50) across 5 principles
- Specific, actionable improvement recommendations
- Before/after examples for key issues
- Option to generate improved version

## Usage

```
Use skill-reviewer to review my [skill-name] skill
```

Or paste SKILL.md content directly.

## Review Process

1. **Read the skill** - Analyzes YAML, body, and resources
2. **Evaluate 5 principles** - Scores each 0-10
3. **Calculate metrics** - Token usage, line count
4. **Generate report** - Structured review with recommendations
5. **Offer improvements** - Can generate improved version

## 5 Principles Evaluated

### 1. Concise is Key (0-10)
- Removes obvious information
- Prefers examples over explanations
- SKILL.md < 500 lines

### 2. Progressive Disclosure (0-10)
- YAML < 100 chars
- Core workflow in SKILL.md
- Details in references/

### 3. Degrees of Freedom (0-10)
- High freedom for creative tasks
- Low freedom for fragile operations
- Medium freedom for standard tasks

### 4. Composability (0-10)
- Works alongside other skills
- No hardcoded paths
- No exclusive assumptions

### 5. Portability (0-10)
- Works on Claude.ai, Claude Code, API
- Dependencies documented
- Fallbacks provided

## Score Interpretation

- **40-50:** Excellent - Minor tweaks only
- **30-39:** Good - Minor improvements needed
- **20-29:** Fair - Significant improvements needed
- **10-19:** Poor - Major refactor required
- **0-9:** Critical - Complete rewrite recommended

## Example Output

```markdown
# Skill Review: my-database-skill

## Overall Score: 28/50 (Fair)

## Principle Scores

| Principle | Score | Status |
|-----------|-------|--------|
| Concise is Key | 4/10 | ⚠️ |
| Progressive Disclosure | 3/10 | ⚠️ |
| Degrees of Freedom | 7/10 | ✅ |
| Composability | 8/10 | ✅ |
| Portability | 6/10 | ⚠️ |

## Issues Found

### Critical
1. YAML description too long (213 chars)
   - Current: "This comprehensive skill provides..."
   - Fix: "Database query and analysis. Use for: SQL, data analysis."

### Important
2. SKILL.md too verbose (1000+ lines)
   - Move API docs to references/api-docs.md
   - Move examples to references/examples.md

## Recommendations

### Quick Wins (< 30 min)
1. Shorten YAML description to < 100 chars
2. Remove "Claude is..." explanations
3. Replace prose with examples

Would you like me to generate an improved version?
```

## What's Included

```
skill-reviewer/
├── SKILL.md (225 lines)
└── references/
    ├── evaluation-criteria.md (Detailed scoring rubric)
    └── common-issues.md (10 common problems with fixes)
```

## Quick Check Mode

For fast review, checks top 5 issues:
1. YAML > 100 chars?
2. SKILL.md > 500 lines?
3. Obvious explanations?
4. No examples?
5. No progressive disclosure?

## Use Cases

- **Before sharing** - Audit skill before team/community distribution
- **Optimization** - Reduce token usage
- **Best practices** - Ensure compliance with official guide
- **Learning** - Understand what makes good skills

## Companion to skill-creator

Use together:
- **skill-creator** - Create new skills
- **skill-reviewer** - Review and improve existing skills

## Credits

Based on Anthropic's "The Complete Guide to Building Skills for Claude"

## License

MIT

## Version

1.0.0 (2026-02-19)
