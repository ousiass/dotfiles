# skill-creator

Enhanced skill creator based on Anthropic's complete 33-page official guide.

## What's Different?

**skill-creator** adds comprehensive best practices from the official guide:

- Token optimization strategies
- Progressive disclosure patterns
- 7 proven skill patterns with examples
- Advanced testing and iteration techniques
- Multi-domain skill structures

## Installation

### Manus
```bash
unzip skill-creator.zip -d ~/skills/
```

### Claude Code
```bash
unzip skill-creator.zip -d ~/.claude/skills/
```

### Claude.ai
Extract and upload via Settings > Capabilities > Skills

## Usage

```
Use skill-creator to help me build a skill for [your task]
```

The skill guides you through:
1. Understanding use case with examples
2. Determining category (standalone/tool/MCP)
3. Planning resources (scripts/references/templates)
4. Designing YAML (under 100 chars)
5. Structuring body (under 500 lines)
6. Setting degrees of freedom (high/medium/low)
7. Writing SKILL.md (imperative, concise)
8. Creating bundled resources
9. Validating (token budget, clarity)
10. Delivering for testing

## Key Principles

### 1. Concise is Key
Claude is already smart. Only add context Claude doesn't have.

### 2. Progressive Disclosure
- YAML: Always loaded (~30-50 tokens)
- Body: Loaded when relevant (<500 lines)
- Files: Discovered as needed

### 3. Degrees of Freedom
- High: Text instructions (multiple approaches)
- Medium: Pseudocode (preferred pattern)
- Low: Exact scripts (fragile operations)

### 4. Composability
Work well alongside other skills.

### 5. Portability
Identical across Claude.ai, Claude Code, API.

## What's Included

```
skill-creator/
├── SKILL.md (228 lines, ~1200 tokens)
└── references/
    ├── patterns.md (7 proven patterns with examples)
    └── advanced.md (token optimization, testing, distribution)
```

## Comparison

| Feature | skill-creator | skill-creator |
|---------|---------------|-------------------|
| Source | Anthropic | Community + Official Guide |
| SKILL.md size | ~240 lines | ~230 lines |
| Patterns | Basic | 7 detailed patterns |
| Token optimization | Mentioned | Detailed strategies |
| Testing guide | Basic | Comprehensive |
| Examples | Few | Many |

## Token Budget

- YAML: <100 chars
- Body: <500 lines (~2500 tokens)
- Total: <5000 tokens

This skill follows its own principles: concise, example-driven, progressive disclosure.

## Credits

- **Based on**: [The Complete Guide to Building Skills for Claude](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf) by Anthropic
- **Inspired by**: [@tetumemo](https://x.com/tetumemo)'s approach
- **Original**: skill-creator by Anthropic

## License

MIT

## Version

1.0.0 (2026-02-19)
