# Advanced Skill Creation Topics

Deep dive into token optimization, testing strategies, and advanced patterns.

## Token Optimization Strategies

### Measuring Token Usage

**Rough estimates:**
- 1 word ≈ 1.3 tokens
- 100 chars ≈ 25 tokens
- 500 lines ≈ 2500 tokens

**Check your skill:**
```bash
# Word count
wc -w SKILL.md

# Multiply by 1.3 for token estimate
```

### Optimization Techniques

**1. Replace prose with examples**

❌ Before (45 tokens):
```markdown
When creating a component, you should consider the props that will be needed, the state management approach, and how the component will integrate with the rest of the application.
```

✅ After (20 tokens):
```markdown
Component checklist:
- Props interface
- State management
- Integration points
```

**2. Use bullet points over paragraphs**

❌ Before (60 tokens):
```markdown
The first step is to analyze the input data. This involves parsing the file format, extracting the relevant fields, and validating that all required information is present. Once this is complete, you can proceed to the transformation step.
```

✅ After (25 tokens):
```markdown
1. Parse input file
2. Extract relevant fields
3. Validate required data
4. Transform to output format
```

**3. Reference external files for details**

❌ Before (200 tokens in SKILL.md):
```markdown
API Authentication:
- Endpoint: https://api.example.com/auth
- Method: POST
- Headers: Content-Type: application/json
- Body: {"username": "...", "password": "..."}
- Response: {"token": "...", "expires": "..."}
[... 150 more tokens of API docs ...]
```

✅ After (15 tokens in SKILL.md + details in references/):
```markdown
For API authentication, see `references/api-auth.md`.
```

**4. Remove obvious information**

❌ Before:
```markdown
Claude is an AI assistant that can help with many tasks. When using this skill, Claude will...
```

✅ After:
```markdown
[Delete entirely - Claude knows what Claude is]
```

**5. Use tables for structured data**

❌ Before (80 tokens):
```markdown
For finance domain, use revenue, profit, and cost metrics. For sales domain, use leads, conversion, and pipeline metrics. For product domain, use features, usage, and adoption metrics.
```

✅ After (40 tokens):
```markdown
| Domain | Metrics |
|--------|---------|
| Finance | Revenue, profit, costs |
| Sales | Leads, conversion, pipeline |
| Product | Features, usage, adoption |
```

### Token Budget Allocation

**Recommended distribution:**

| Component | Target | Max |
|-----------|--------|-----|
| YAML description | 50 tokens | 100 tokens |
| SKILL.md body | 1500 tokens | 2500 tokens |
| Each reference file | 1000 tokens | 5000 tokens |
| Total skill | 3000 tokens | 5000 tokens |

**If exceeding budget:**
1. Remove obvious explanations
2. Replace prose with examples
3. Move details to references/
4. Use tables instead of paragraphs
5. Delete redundant information

## Multi-Domain Skill Structures

### Pattern 1: Reference-Based Domains

**Use when:** Each domain has different data/procedures

**Structure:**
```
skill-name/
├── SKILL.md (navigation logic)
└── references/
    ├── domain-a.md
    ├── domain-b.md
    └── domain-c.md
```

**SKILL.md example:**
```markdown
## Domain Detection

Identify domain from user query:
- Keywords X, Y → `references/domain-a.md`
- Keywords P, Q → `references/domain-b.md`

Read relevant reference for domain-specific workflow.
```

**When to use:**
- Multi-department reporting
- Industry-specific analysis
- Role-based workflows

### Pattern 2: Script-Based Variants

**Use when:** Same workflow, different implementations

**Structure:**
```
skill-name/
├── SKILL.md (core workflow)
└── scripts/
    ├── variant-a.py
    ├── variant-b.py
    └── variant-c.py
```

**SKILL.md example:**
```markdown
## Processing Workflow

1. Detect input format
2. Run appropriate script:
   - PDF → `scripts/process-pdf.py`
   - DOCX → `scripts/process-docx.py`
   - HTML → `scripts/process-html.py`
3. Validate output
```

**When to use:**
- Multiple file formats
- Platform-specific operations
- Algorithm variants

### Pattern 3: Template-Based Outputs

**Use when:** Same process, different output formats

**Structure:**
```
skill-name/
├── SKILL.md (generation workflow)
└── templates/
    ├── format-a.html
    ├── format-b.md
    └── format-c.json
```

**SKILL.md example:**
```markdown
## Output Generation

1. Gather required data
2. Select template based on user preference:
   - Web → `templates/web.html`
   - Document → `templates/doc.md`
   - API → `templates/api.json`
3. Populate template with data
```

**When to use:**
- Multiple output formats
- Brand-specific templates
- Localization variants

## Conditional Workflow Patterns

### Pattern 1: If-Then Logic

```markdown
## Workflow

1. Check input type:
   - If file path → read file
   - If URL → fetch content
   - If text → use directly

2. Validate content:
   - If invalid → request correction
   - If valid → proceed

3. Process based on size:
   - If <1000 words → inline processing
   - If >1000 words → use `scripts/batch-process.py`
```

### Pattern 2: Error Recovery

```markdown
## Workflow with Error Handling

1. Attempt API call
2. If 401 error:
   - Re-authenticate using `scripts/auth.py`
   - Retry original request
3. If 429 error:
   - Wait 60 seconds
   - Retry with exponential backoff
4. If 500 error:
   - Report to user
   - Suggest alternative approach
```

### Pattern 3: Progressive Enhancement

```markdown
## Analysis Workflow

1. Basic analysis (always):
   - Descriptive statistics
   - Data quality checks

2. If time-series data:
   - Trend analysis
   - Seasonality detection

3. If categorical data:
   - Distribution analysis
   - Chi-square tests

4. If user requests:
   - Advanced modeling
   - Predictive analysis
```

## Testing and Iteration

### Testing Checklist

**Before first use:**
- [ ] YAML description triggers on expected queries
- [ ] SKILL.md loads when skill triggers
- [ ] All scripts execute without errors
- [ ] Reference files are readable
- [ ] Templates are valid

**After first use:**
- [ ] Skill produces expected output
- [ ] No unnecessary clarifying questions
- [ ] Token usage is reasonable
- [ ] Works alongside other skills
- [ ] Handles edge cases

### Iteration Strategies

**Problem: Skill doesn't trigger**

Symptoms:
- Claude doesn't use skill when expected
- Skill never loads

Solutions:
1. Improve YAML description specificity
2. Add trigger keywords
3. Include use case examples in description

Example fix:
```yaml
# Before
description: Helps with documents

# After
description: Create and edit .docx files with tracked changes. Use for: Word documents, change tracking, document formatting.
```

**Problem: Too many clarifying questions**

Symptoms:
- Claude asks obvious questions
- Workflow stalls frequently

Solutions:
1. Lower degrees of freedom
2. Add default assumptions
3. Provide decision tree

Example fix:
```markdown
# Before
Analyze the data and create a report.

# After
Analyze the data:
1. Descriptive statistics (always)
2. Correlation analysis (if >2 variables)
3. Time-series analysis (if date column present)

Generate report using `templates/analysis-report.md`.
```

**Problem: Inconsistent output**

Symptoms:
- Results vary widely between runs
- Quality is unpredictable

Solutions:
1. Add specific examples
2. Include quality criteria
3. Provide validation script

Example fix:
```markdown
# Before
Create a professional report.

# After
Create report with:
- Executive summary (2-3 paragraphs)
- Findings (3-5 sections)
- Recommendations (numbered list)
- Appendix (supporting data)

Validate using `scripts/validate-report.py` before delivery.
```

**Problem: Token budget exceeded**

Symptoms:
- Skill truncated in context
- Other content pushed out

Solutions:
1. Move details to references/
2. Replace prose with examples
3. Use tables instead of paragraphs
4. Remove obvious information

Example fix:
```markdown
# Before (in SKILL.md, 500 tokens)
[Long API documentation...]

# After (in SKILL.md, 20 tokens)
For API details, see `references/api-docs.md`.

Read when:
- Making API calls
- Handling errors
- Understanding rate limits
```

### A/B Testing Skills

**Method:**
1. Create two versions of the skill
2. Test on same set of tasks
3. Compare:
   - Output quality
   - Token usage
   - Time to completion
   - Number of clarifying questions
4. Keep better version

**Example comparison:**

| Metric | Version A | Version B |
|--------|-----------|-----------|
| Token usage | 3500 | 2000 |
| Clarifying questions | 3 | 1 |
| Output quality | Good | Good |
| Time to completion | 2 min | 1.5 min |

Version B wins: Same quality, more efficient.

## Distribution Strategies

### For Personal Use

**Local development:**
```bash
# Keep in skills directory
~/skills/my-skill/

# Version control
cd ~/skills/my-skill
git init
git add .
git commit -m "Initial version"
git tag v1.0.0
```

**Iteration workflow:**
1. Use skill on real tasks
2. Note improvements needed
3. Edit SKILL.md or resources
4. Test changes
5. Commit with descriptive message

### For Team Use

**Internal repository:**
```bash
# Create internal repo
gh repo create company/my-skill --private

# Clone and develop
gh repo clone company/my-skill
cd my-skill
# ... develop skill ...
git push
```

**Documentation for team:**
- README.md (setup instructions)
- EXAMPLES.md (usage examples)
- CHANGELOG.md (version history)

**Note:** These files are for humans, not included in the skill directory.

### For Community

**Public distribution:**

1. **Create GitHub repo**
   ```bash
   gh repo create username/my-skill --public
   ```

2. **Add documentation**
   - README.md (description, installation, usage)
   - LICENSE (MIT recommended)
   - EXAMPLES.md (real-world examples)

3. **Submit to awesome-claude-skills**
   - Fork travisvn/awesome-claude-skills
   - Add your skill to appropriate category
   - Submit pull request

4. **Promote**
   - Share on X/Twitter
   - Post in Claude communities
   - Write blog post

**Quality checklist for public skills:**
- [ ] Clear, specific description
- [ ] Comprehensive README
- [ ] Working examples
- [ ] No hardcoded secrets or paths
- [ ] Tested on multiple platforms
- [ ] License included

## Advanced MCP Integration

### Pattern: Skill as MCP Workflow Layer

**MCP provides:** Raw tool access

**Skill provides:** Workflow, best practices, error handling

**Example structure:**

```markdown
# Database Analysis Skill

## Prerequisites

Requires MCP server with tools:
- `list_tables`
- `describe_table`
- `query_db`

## Workflow

1. **Schema discovery**
   ```
   Use list_tables to see available tables.
   Use describe_table for relevant tables.
   ```

2. **Query construction**
   - Check `references/query-patterns.md` for common patterns
   - Optimize for performance (see `references/optimization.md`)
   - Validate syntax before execution

3. **Execution**
   ```
   Use query_db with constructed query.
   ```

4. **Error handling**
   - Syntax error → show query, ask for fix
   - Timeout → suggest optimization
   - Permission error → check available tables

5. **Result formatting**
   - <20 rows → markdown table
   - >20 rows → CSV file
   - Include summary statistics
```

**Benefits:**
- Consistent usage patterns
- Error handling built-in
- Best practices encoded
- Easier onboarding

### Pattern: Skill + MCP + Scripts

**Combine all three for maximum power:**

```
database-skill/
├── SKILL.md (workflow + MCP tool usage)
├── scripts/
│   ├── optimize-query.py (query optimization)
│   └── format-results.py (result formatting)
└── references/
    ├── query-patterns.md (common patterns)
    └── optimization.md (performance tips)
```

**Workflow:**
1. MCP tools for data access
2. Scripts for complex processing
3. References for domain knowledge
4. SKILL.md orchestrates everything

## Troubleshooting Complex Skills

### Issue: Skill conflicts with other skills

**Diagnosis:**
- Multiple skills trigger on same query
- Skills have overlapping functionality

**Solutions:**
1. Make YAML descriptions more specific
2. Add exclusion criteria
3. Combine into single skill

**Example:**
```yaml
# Skill A
description: Generate React components from specs

# Skill B
description: Generate Vue components from specs

# Better: Combined skill
description: Generate frontend components (React/Vue) from specs. Detect framework from user query or ask.
```

### Issue: Skill works in Claude.ai but not Claude Code

**Diagnosis:**
- Environment differences
- Missing dependencies

**Solutions:**
1. Document dependencies in SKILL.md
2. Add environment detection
3. Provide fallback approaches

**Example:**
```markdown
## Environment Requirements

- Python 3.8+ with pandas
- Node.js 18+ (for template processing)

If dependencies missing:
- Python: Use built-in csv module instead of pandas
- Node.js: Use Python jinja2 for templates
```

### Issue: Skill performance degrades over time

**Diagnosis:**
- Context window fills up
- Too many reference files loaded

**Solutions:**
1. Reduce token usage
2. Be more selective about loading references
3. Use scripts instead of inline processing

**Example:**
```markdown
# Before
Read all reference files at start.

# After
Read reference files only when specific domain detected:
- Finance query → `references/finance.md`
- Sales query → `references/sales.md`
```

## Measuring Skill Success

**Quantitative metrics:**
- Token usage per task
- Time to completion
- Number of clarifying questions
- Error rate

**Qualitative metrics:**
- Output quality
- User satisfaction
- Ease of use
- Consistency

**Improvement targets:**
- Reduce token usage by 30%
- Reduce clarifying questions by 50%
- Maintain or improve output quality
- Increase consistency to >90%

**Tracking:**
```markdown
# skill-metrics.md

## Version 1.0.0 (2026-01-15)
- Avg tokens: 3500
- Avg questions: 3
- Quality: Good
- Consistency: 70%

## Version 1.1.0 (2026-02-01)
- Avg tokens: 2000 (↓43%)
- Avg questions: 1 (↓67%)
- Quality: Good (→)
- Consistency: 90% (↑20%)

Changes:
- Moved API docs to references/
- Added decision tree for common cases
- Included validation script
```

## Resources

**Official:**
- [Complete Guide PDF](https://resources.anthropic.com/hubfs/The-Complete-Guide-to-Building-Skill-for-Claude.pdf)
- [Skills Documentation](https://docs.anthropic.com/claude/docs/skills)
- [Skills Repository](https://github.com/anthropics/skills)

**Community:**
- [Awesome Claude Skills](https://github.com/travisvn/awesome-claude-skills)
- [Claude Cookbooks](https://github.com/anthropics/anthropic-cookbook)

**Tools:**
- skill-creator: Official skill creation tool
- skill-creator: This enhanced version
