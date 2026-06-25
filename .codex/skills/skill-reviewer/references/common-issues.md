# Common Issues and Fixes

Real-world examples of skill problems and how to fix them.

## Issue 1: Verbose YAML Description

### Problem
YAML description is too long, wastes tokens, unclear triggers.

### Example

**Bad:**
```yaml
description: This comprehensive skill provides detailed guidance for creating, editing, and managing Word documents with advanced features including tracked changes, comments, formatting, and collaboration tools. It supports both .docx and .doc formats and integrates with various document management systems.
```
**Length:** 287 chars  
**Issues:** Too long, obvious details, unclear when to trigger

**Good:**
```yaml
description: Create and edit .docx files with tracked changes. Use for: Word documents, change tracking, document formatting.
```
**Length:** 107 chars  
**Issues:** None

### Fix Strategy

1. Remove "This skill..." preamble
2. State what it does (verb phrase)
3. Add "Use for:" with 3-4 trigger keywords
4. Target: < 100 chars

## Issue 2: Obvious Explanations

### Problem
Explains things Claude already knows, wastes tokens.

### Example

**Bad:**
```markdown
## Understanding User Requirements

Before you begin any task, it's crucial to understand what the user 
wants. This involves carefully reading their request, asking clarifying 
questions if anything is unclear, and making sure you have all the 
information needed to complete the task successfully. Good communication 
is key to delivering high-quality results.
```
**Tokens:** ~60  
**Issues:** Claude knows this already

**Good:**
```markdown
[Delete entirely - Claude knows to understand requirements]
```
**Tokens:** 0  
**Savings:** 60 tokens

### Fix Strategy

Delete any section that explains:
- How to read user requests
- Why communication is important
- What Claude is or does
- Basic problem-solving approaches
- General best practices Claude knows

## Issue 3: Prose Instead of Examples

### Problem
Long paragraphs explaining concepts instead of showing examples.

### Example

**Bad:**
```markdown
When creating a React component, you should think about the component's 
purpose and how it will be used. Consider what props it needs to accept, 
what state it might need to manage, and how it will render its output. 
Think about edge cases and error handling. Make sure the component is 
reusable and follows React best practices.
```
**Tokens:** ~65  
**Issues:** All prose, no examples, vague

**Good:**
```markdown
React component template:

```tsx
interface Props {
  name: string;
  onAction?: () => void;
}

export const MyComponent = ({ name, onAction }: Props) => {
  const [state, setState] = useState(false);
  
  return (
    <div onClick={onAction}>
      {name}: {state ? 'Active' : 'Inactive'}
    </div>
  );
};
```

Checklist:
- [ ] Props interface
- [ ] State if needed
- [ ] Error handling
- [ ] TypeScript types
```
**Tokens:** ~45  
**Issues:** None, shows instead of tells

### Fix Strategy

Replace prose with:
1. Code examples
2. Templates
3. Checklists
4. Before/after comparisons

## Issue 4: No Progressive Disclosure

### Problem
Everything in SKILL.md, no use of references/.

### Example

**Bad Structure:**
```
my-skill/
└── SKILL.md (1500 lines)
    ├── Core workflow
    ├── API documentation (300 lines)
    ├── Database schemas (200 lines)
    ├── Example queries (400 lines)
    └── Troubleshooting (200 lines)
```
**Issues:** Everything loaded always, 1500 lines

**Good Structure:**
```
my-skill/
├── SKILL.md (300 lines)
│   ├── Core workflow
│   └── Navigation to references
└── references/
    ├── api-docs.md (API documentation)
    ├── schemas.md (Database schemas)
    ├── examples.md (Example queries)
    └── troubleshooting.md (Troubleshooting)
```
**Issues:** None, progressive loading

### Fix Strategy

1. Keep core workflow in SKILL.md (< 500 lines)
2. Move to references/:
   - API documentation
   - Schemas and data models
   - Extensive examples
   - Troubleshooting guides
   - Domain-specific details
3. Add clear navigation in SKILL.md:
   ```markdown
   For API details, see `references/api-docs.md`
   For examples, see `references/examples.md`
   ```

## Issue 5: Wrong Degrees of Freedom

### Problem
Too vague for fragile operations or too rigid for creative tasks.

### Example A: Too Vague for Fragile Operation

**Bad:**
```markdown
Set up the database connection and run the migration.
```
**Issues:** Database setup is fragile, needs exact steps

**Good:**
```markdown
Database setup (use exact script):

```bash
#!/bin/bash
export DB_HOST=localhost
export DB_PORT=5432
export DB_NAME=myapp
export DB_USER=admin

# Run migration
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -f migrations/001_init.sql

# Verify
psql -h $DB_HOST -p $DB_PORT -U $DB_USER -d $DB_NAME -c "\dt"
```

If errors, see `references/troubleshooting.md`
```
**Issues:** None, exact steps for fragile operation

### Example B: Too Rigid for Creative Task

**Bad:**
```markdown
Generate blog post using this exact structure:
1. Title must be exactly 60 characters
2. Introduction must be exactly 3 paragraphs
3. Body must have exactly 5 sections
4. Each section must be exactly 200 words
5. Conclusion must be exactly 2 paragraphs
```
**Issues:** Too rigid, kills creativity

**Good:**
```markdown
Generate blog post:

Structure:
- Title (60-80 chars, includes keyword)
- Introduction (2-3 paragraphs)
- Body (3-5 sections, ~200 words each)
- Conclusion (1-2 paragraphs)

Adapt structure based on topic and audience.
```
**Issues:** None, guidance with flexibility

### Fix Strategy

**For fragile operations (low freedom):**
- Provide exact scripts
- Specify exact sequence
- Include error handling
- Validate each step

**For creative tasks (high freedom):**
- Provide guidelines, not rules
- Show examples, not templates
- Allow adaptation
- Trust Claude's judgment

**For standard tasks (medium freedom):**
- Provide preferred pattern
- Allow reasonable variation
- Include decision points
- Show common approaches

## Issue 6: Hardcoded Paths

### Problem
Hardcoded file paths prevent composability.

### Example

**Bad:**
```markdown
Save output to /tmp/analysis_result.txt
Save logs to /var/log/myskill.log
```
**Issues:** Conflicts with other skills, not portable

**Good:**
```markdown
Save output to user-specified path.

Default locations:
- Output: `$MYSKILL_OUTPUT_DIR/result.txt` or ask user
- Logs: `$MYSKILL_LOG_DIR/myskill.log` or skip logging

Ask user: "Where should I save the analysis result?"
```
**Issues:** None, flexible and composable

### Fix Strategy

1. Use environment variables with skill prefix
2. Ask user for paths
3. Provide sensible defaults
4. Never assume specific paths exist

## Issue 7: Platform-Specific Code

### Problem
Code only works on one platform.

### Example

**Bad:**
```markdown
Use the Claude Code file browser to select input files.
Press Cmd+Shift+P to open command palette.
```
**Issues:** Claude Code only, not portable

**Good:**
```markdown
## File Selection

**Claude Code:**
- Use file browser to select files
- Or use command: `/file select`

**Claude.ai:**
- Upload files via attachment
- Or paste content directly

**API:**
- Provide file paths in request
- Or send content in message

## Keyboard Shortcuts

**macOS:** Cmd+Shift+P  
**Windows/Linux:** Ctrl+Shift+P  
**Claude.ai:** Not applicable
```
**Issues:** None, covers all platforms

### Fix Strategy

1. Document behavior for each platform
2. Provide fallbacks
3. Use platform detection if needed
4. Keep platform-specific code in scripts/, not SKILL.md

## Issue 8: Missing Examples

### Problem
Instructions without examples are hard to follow.

### Example

**Bad:**
```markdown
## API Integration

Integrate with the external API following best practices. Handle 
authentication, rate limiting, and errors appropriately.
```
**Issues:** Vague, no examples, unclear

**Good:**
```markdown
## API Integration

Example workflow:

```python
import requests
from time import sleep

# 1. Authenticate
response = requests.post(
    "https://api.example.com/auth",
    json={"api_key": API_KEY}
)
token = response.json()["token"]

# 2. Make request with rate limiting
headers = {"Authorization": f"Bearer {token}"}
try:
    response = requests.get(
        "https://api.example.com/data",
        headers=headers
    )
    response.raise_for_status()
    data = response.json()
except requests.exceptions.HTTPError as e:
    if e.response.status_code == 429:
        sleep(60)  # Rate limited, wait
        # Retry logic here
    else:
        raise
```

For full API docs, see `references/api-docs.md`
```
**Issues:** None, clear example

### Fix Strategy

Add examples for:
- API calls
- Data transformations
- Error handling
- Common workflows
- Edge cases

## Issue 9: No Validation

### Problem
No way to verify output quality.

### Example

**Bad:**
```markdown
Generate a report and deliver to user.
```
**Issues:** No quality check, inconsistent output

**Good:**
```markdown
Generate report:

1. Create content following template
2. Validate using checklist:
   - [ ] Executive summary present
   - [ ] All sections included
   - [ ] Data sources cited
   - [ ] Recommendations specific
   - [ ] Length 1000-1500 words
3. If validation fails, revise
4. Deliver to user

Optional: Run `scripts/validate-report.py` for automated check
```
**Issues:** None, quality assured

### Fix Strategy

Add validation:
- Checklists for manual review
- Scripts for automated validation
- Quality criteria
- Required elements
- Format requirements

## Issue 10: Unclear Navigation

### Problem
References exist but unclear when to read them.

### Example

**Bad:**
```markdown
See references/ for more information.
```
**Issues:** Vague, Claude doesn't know which file or when

**Good:**
```markdown
## Domain-Specific Analysis

Identify domain from user query:

- **Finance** (revenue, profit, costs) → `references/finance.md`
- **Sales** (leads, conversion, pipeline) → `references/sales.md`
- **Product** (features, usage, adoption) → `references/product.md`

Read relevant reference for:
- Key metrics
- Data sources
- Analysis patterns
- Reporting format
```
**Issues:** None, clear navigation

### Fix Strategy

For each reference file, specify:
1. When to read it (trigger conditions)
2. What it contains
3. How to use the information

## Quick Fix Checklist

Run through this checklist for fast improvements:

### YAML
- [ ] Description < 100 chars
- [ ] Includes "Use for:" with keywords
- [ ] No obvious details

### SKILL.md Body
- [ ] < 500 lines
- [ ] No "Claude is..." or "You should..."
- [ ] Examples over prose
- [ ] Clear structure

### Progressive Disclosure
- [ ] Core workflow in SKILL.md
- [ ] Details in references/
- [ ] Clear navigation

### Degrees of Freedom
- [ ] Low freedom for fragile operations
- [ ] High freedom for creative tasks
- [ ] Medium freedom for standard tasks

### Composability
- [ ] No hardcoded paths
- [ ] No global state assumptions
- [ ] Namespaced variables

### Portability
- [ ] Works on all platforms
- [ ] Dependencies documented
- [ ] Fallbacks provided

## Before/After Examples

### Example 1: Database Query Skill

**Before (Score: 18/50):**
```markdown
---
description: This skill helps you work with databases by providing comprehensive guidance for querying, analyzing, and managing database operations.
---

# Database Helper

This skill will help you work with databases effectively.

## Introduction

Databases are important for storing and retrieving data. When working 
with databases, you need to understand SQL and how to construct queries...

[... 800 more lines of obvious explanations ...]
```

**After (Score: 44/50):**
```markdown
---
description: Database query and analysis. Use for: SQL queries, data analysis, schema design.
---

# Database Query Skill

## Quick Query Workflow

1. **Understand schema**
   ```sql
   \dt  -- List tables
   \d table_name  -- Describe table
   ```

2. **Construct query**
   - Simple: Direct SELECT
   - Complex: See `references/query-patterns.md`

3. **Execute and format**
   - < 20 rows: Markdown table
   - > 20 rows: CSV file

## Examples

**Find top customers:**
```sql
SELECT customer_id, SUM(amount) as total
FROM orders
WHERE date > '2024-01-01'
GROUP BY customer_id
ORDER BY total DESC
LIMIT 10;
```

For more patterns, see `references/query-patterns.md`
```

**Improvements:**
- YAML: 213 chars → 81 chars
- Body: 1000+ lines → 200 lines
- Added examples
- Progressive disclosure
- Removed obvious content

### Example 2: Code Generation Skill

**Before (Score: 22/50):**
```markdown
---
description: Generate code
---

# Code Generator

Generate code based on user requirements. Make sure to write clean,
well-documented code that follows best practices...

[... vague instructions continue ...]
```

**After (Score: 42/50):**
```markdown
---
description: Generate React/Vue/Angular components from specs. Use for: frontend components, UI code.
---

# Component Generator

## Workflow

1. **Detect framework** (React/Vue/Angular or ask)
2. **Analyze requirements**
   - Component purpose
   - Props/inputs
   - State needs
3. **Generate using template**
   - React: `templates/react-component.tsx`
   - Vue: `templates/vue-component.vue`
   - Angular: `templates/angular-component.ts`
4. **Add tests** (optional)

## Example: React Component

Input: "User profile card with avatar, name, bio"

Output:
```tsx
interface ProfileCardProps {
  avatar: string;
  name: string;
  bio: string;
}

export const ProfileCard = ({ avatar, name, bio }: ProfileCardProps) => (
  <div className="profile-card">
    <img src={avatar} alt={name} />
    <h2>{name}</h2>
    <p>{bio}</p>
  </div>
);
```

Adapt structure based on requirements.
```

**Improvements:**
- YAML: 14 chars → 93 chars (more specific)
- Added framework detection
- Concrete examples
- Template references
- Appropriate freedom level
