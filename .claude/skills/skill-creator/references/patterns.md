# Common Skill Patterns

Detailed examples of proven skill patterns from Anthropic's official guide.

## Pattern 1: Document Processing

**Structure:**
- Input: File path or content
- Process: Parse → Transform → Validate
- Output: Structured result

**Degrees of freedom:** Medium (specific steps, some variation)

**Example SKILL.md snippet:**

```markdown
## Workflow

1. Parse input file using appropriate library
2. Extract structured data:
   - Headers → metadata
   - Tables → dataframes
   - Text → paragraphs
3. Transform to target format
4. Validate output structure
5. Save to specified path

## Example

Input: `report.pdf`
Output: `report.md` with:
- YAML frontmatter (title, date, author)
- Markdown sections
- Tables as markdown tables
```

**Use cases:**
- PDF to Markdown conversion
- Excel data extraction
- Word document formatting

## Pattern 2: Code Generation

**Structure:**
- Input: Specifications or requirements
- Process: Template selection → Customization
- Output: Working code

**Degrees of freedom:** High (many valid approaches)

**Example SKILL.md snippet:**

```markdown
## Workflow

Analyze requirements and generate appropriate code structure.

Consider:
- Framework conventions
- Project structure
- Error handling patterns
- Testing requirements

Use templates from `templates/` as starting points.

## Example

Input: "Create React component for user profile card"

Output:
- Component file with TypeScript
- Props interface
- Basic styling
- Unit test skeleton
```

**Use cases:**
- React component generation
- API client creation
- Database schema design

## Pattern 3: API Integration

**Structure:**
- Input: User request
- Process: Format request → Call API → Parse response
- Output: Formatted result

**Degrees of freedom:** Low (exact API requirements)

**Example SKILL.md snippet:**

```markdown
## Workflow

Use exact API calling pattern:

1. Format request:
   ```python
   headers = {"Authorization": f"Bearer {token}"}
   params = {"query": user_query, "limit": 10}
   ```

2. Call API using `scripts/api_client.py`:
   ```bash
   python scripts/api_client.py --endpoint search --params params.json
   ```

3. Parse response:
   - Extract `data.results[]`
   - Format as markdown table
   - Handle errors from `data.error`

## Error Handling

- 401: Re-authenticate
- 429: Wait 60s, retry
- 500: Report to user
```

**Use cases:**
- Weather data retrieval
- Payment processing
- External service calls

## Pattern 4: MCP-Enhanced Workflow

**Structure:**
- MCP provides: Tools and data access
- Skill provides: Workflow and best practices
- Result: Optimized, consistent usage

**Degrees of freedom:** Medium (guided workflow with flexibility)

**Example SKILL.md snippet:**

```markdown
## Database Query Workflow

When user requests data analysis:

1. **Understand schema**
   - Use `list_tables` tool
   - Check `references/schema.md` for business logic

2. **Clarify requirements**
   Ask about:
   - Time range
   - Aggregation level
   - Specific metrics

3. **Construct query**
   - Use `query_db` tool
   - Follow patterns in `references/query-patterns.md`
   - Optimize for performance

4. **Format results**
   - Markdown table for <20 rows
   - CSV file for >20 rows
   - Include summary statistics

5. **Provide insights**
   - Highlight trends
   - Note anomalies
   - Suggest follow-up queries
```

**Use cases:**
- Database analysis workflows
- File system operations
- External service orchestration

## Pattern 5: Multi-Step Process

**Structure:**
- Sequential steps with dependencies
- Conditional logic based on outcomes
- State management across steps

**Degrees of freedom:** Medium (clear sequence, some adaptation)

**Example SKILL.md snippet:**

```markdown
## Research Workflow

1. **Initial search**
   - Use search tool with user query
   - Collect 5-10 relevant sources

2. **Source evaluation**
   For each source:
   - Check credibility (domain, date, author)
   - Extract key claims
   - Note supporting evidence

3. **Synthesis**
   - Group related claims
   - Identify consensus vs. disagreement
   - Note gaps in information

4. **Output**
   Generate report with:
   - Executive summary
   - Findings by topic
   - Source citations
   - Confidence levels
```

**Use cases:**
- Research workflows
- Content creation pipelines
- Data processing chains

## Pattern 6: Output Quality Control

**Structure:**
- Template-based generation
- Quality criteria
- Validation steps

**Degrees of freedom:** Low (specific quality standards)

**Example SKILL.md snippet:**

```markdown
## Blog Post Generation

Use template from `templates/blog-post.md`.

Required sections:
1. Title (60-80 chars, includes keyword)
2. Introduction (2-3 paragraphs)
3. Body (3-5 H2 sections)
4. Conclusion (1-2 paragraphs)
5. Call-to-action

Quality criteria:
- [ ] Flesch reading ease: 60-70
- [ ] Sentences: <25 words average
- [ ] Paragraphs: 3-5 sentences
- [ ] Images: 1 per section
- [ ] Internal links: 2-3
- [ ] External links: 1-2

Validate using `scripts/validate_post.py` before delivery.
```

**Use cases:**
- Content creation with style guides
- Code with linting requirements
- Documents with formatting standards

## Pattern 7: Progressive Disclosure (Multi-Domain)

**Structure:**
- Core workflow in SKILL.md
- Domain-specific details in references/
- Claude navigates as needed

**Degrees of freedom:** High (domain-dependent)

**Example SKILL.md snippet:**

```markdown
## Multi-Domain Analysis

1. Identify domain from user query:
   - Finance → `references/finance.md`
   - Sales → `references/sales.md`
   - Product → `references/product.md`

2. Read relevant reference file for:
   - Key metrics
   - Data sources
   - Analysis patterns

3. Execute domain-specific analysis

4. Format output per domain conventions

## When to Read References

- Finance: Mentions revenue, profit, costs, budget
- Sales: Mentions leads, conversion, pipeline, deals
- Product: Mentions features, usage, adoption, churn
```

**File structure:**
```
multi-domain-skill/
├── SKILL.md (navigation + core workflow)
└── references/
    ├── finance.md (CFO metrics, financial analysis)
    ├── sales.md (Sales KPIs, funnel analysis)
    └── product.md (Product metrics, user analysis)
```

**Use cases:**
- Multi-department reporting
- Domain-specific analysis
- Role-based workflows

## Choosing the Right Pattern

| Pattern | Use When | Freedom |
|---------|----------|---------|
| Document Processing | Consistent input/output formats | Medium |
| Code Generation | Creative solutions needed | High |
| API Integration | Exact specifications required | Low |
| MCP-Enhanced | Existing tools need workflow | Medium |
| Multi-Step Process | Sequential dependencies | Medium |
| Output Quality | Specific standards required | Low |
| Progressive Disclosure | Multiple domains/variants | High |

## Combining Patterns

Skills often combine multiple patterns:

**Example: "Research Report Generator"**
- Multi-Step Process (research workflow)
- Output Quality Control (report standards)
- Document Processing (format sources)

**Example: "Database Dashboard Builder"**
- MCP-Enhanced (database access)
- Code Generation (dashboard code)
- API Integration (external data)

## Anti-Patterns to Avoid

**❌ Kitchen Sink Skill**
```markdown
This skill does everything: research, coding, analysis, design...
```
Better: Create focused skills that compose naturally.

**❌ Obvious Explanations**
```markdown
First, you need to understand what the user wants. This is important because...
```
Better: Assume Claude knows general principles.

**❌ Verbose Examples**
```markdown
For example, if the user asks for X, you should do Y because Z, and then...
```
Better: Show concise before/after examples.

**❌ Duplicate Information**
```markdown
# SKILL.md
API endpoint: https://api.example.com/v1/search

# references/api-docs.md
API endpoint: https://api.example.com/v1/search
```
Better: Reference once, link from SKILL.md.

**❌ No Degrees of Freedom**
```markdown
Analyze the data and create a report.
```
Better: Specify structure, format, or provide template.

## Testing Your Pattern

1. **Use the skill** on real examples
2. **Notice struggles**: Where does Claude hesitate or ask for clarification?
3. **Identify gaps**: What information is missing?
4. **Adjust freedom**: Too vague? Add structure. Too rigid? Loosen constraints.
5. **Iterate**: Test again with improvements

Good skills feel natural to use and produce consistent results.
