---
name: skill-creator
description: Enhanced skill creator based on Anthropic's 33-page official guide. Use for creating high-quality skills with complete best practices, progressive disclosure patterns, and token optimization strategies.
---

# Skill Creator Max

Enhanced skill creator incorporating Anthropic's complete official guide. Provides comprehensive best practices beyond the standard skill-creator.

## Core Principles (from Official Guide)

### 1. Concise is Key

**Default assumption: Claude is already very smart.** Only add context Claude doesn't have.

Challenge each piece: "Does this justify its token cost?"

Prefer examples over explanations.

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

Work well alongside other skills. Don't assume exclusive access.

### 5. Portability

Identical behavior across Claude.ai, Claude Code, and API.

## Skill Creation Workflow

### Step 1: Understand with Examples

Ask user:
- "What task should this skill handle?"
- "Give me 2-3 examples of how you'd use it"
- "What stays the same vs. what varies?"

Conclude when you have clear sense of functionality.

### Step 2: Determine Category

**Category 1: Standalone workflow**
- No external tools needed
- Example: Document formatting, code review checklist

**Category 2: Tool integration**
- Specific file formats or APIs
- Example: PDF processing, API patterns

**Category 3: MCP-enhanced**
- Works with existing MCP server
- Example: Database workflows, external services

### Step 3: Plan Resources

Identify what to bundle:

| Resource | When to Use | Example |
|----------|-------------|---------|
| `scripts/` | Code rewritten repeatedly | `rotate_pdf.py` |
| `templates/` | Same boilerplate each time | HTML starter |
| `references/` | Documentation needed repeatedly | API schemas |

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

Use imperative form. Be direct.

**Frontmatter:**
- `name`: skill-name (lowercase with hyphens)
- `description`: What it does + when to use it (<100 chars)

**Body:**
- Start with what, not why
- Use examples, not explanations
- Reference bundled files explicitly
- Keep under 500 lines

### Step 8: Create Bundled Resources

**scripts/**: Executable code
- Include shebang
- Document parameters in comments
- Test before including

**references/**: Documentation
- Loaded only as needed
- API docs, schemas, examples
- Include grep patterns in SKILL.md for large files (>10k words)

**templates/**: Static files
- Not loaded into context
- HTML templates, config files, assets

**Avoid duplication:** Info lives in SKILL.md OR references, not both.

### Step 9: Validate

Check:
- [ ] YAML description under 100 chars
- [ ] Body under 500 lines
- [ ] Examples over explanations
- [ ] No obvious information Claude already knows
- [ ] Clear when to read each reference file
- [ ] Scripts tested and working

### Step 10: Deliver

Package and send to user for testing.

## Common Patterns

See `/home/ubuntu/skill-creator/references/patterns.md` for detailed examples:
- Document processing workflows
- Code generation patterns
- API integration patterns
- MCP-enhanced workflows

## Advanced Topics

See `/home/ubuntu/skill-creator/references/advanced.md` for:
- Token optimization strategies
- Multi-domain skill structures
- Conditional workflow patterns
- Testing and iteration techniques

## Kitchen Analogy

**MCP = Professional kitchen** (tools, ingredients, equipment)

**Skills = Recipes** (step-by-step instructions)

**Claude = Chef** (knows general principles, follows recipes for consistency)

If you have working MCP server, skills are the knowledge layer on top.

## Quick Reference

**Token budget:**
- YAML: <100 chars
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

**Don't include:** README.md, CHANGELOG.md, LICENSE (skills are for AI, not users)

## Let's Build

Ready to create a skill? Start by answering:

**What task or workflow should this skill handle?**

Give me 2-3 concrete examples of how you'd use it.
