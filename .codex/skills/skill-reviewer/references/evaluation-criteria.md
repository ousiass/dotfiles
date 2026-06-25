# Evaluation Criteria

Detailed scoring rubric for each of the 5 principles from Anthropic's official guide.

## 1. Concise is Key (0-10 points)

**Principle:** Claude is already smart. Only add context Claude doesn't have.

### Scoring Rubric

**10 points - Excellent**
- Zero obvious explanations
- Examples preferred over prose
- Every sentence justifies token cost
- SKILL.md < 300 lines

**7-9 points - Good**
- Minimal obvious explanations
- Mix of examples and prose
- Most content is valuable
- SKILL.md < 500 lines

**4-6 points - Fair**
- Some obvious explanations
- More prose than examples
- Some unnecessary content
- SKILL.md 500-800 lines

**1-3 points - Poor**
- Many obvious explanations
- Mostly prose, few examples
- Lots of unnecessary content
- SKILL.md > 800 lines

**0 points - Critical**
- Explains basic concepts
- No examples, all prose
- Extremely verbose
- SKILL.md > 1500 lines

### Red Flags

❌ "Claude is an AI assistant that..."
❌ "You should first understand..."
❌ "It's important to..."
❌ Long paragraphs explaining obvious things
❌ Repetitive content

### Good Patterns

✅ Direct instructions
✅ Concise examples
✅ Bullet points over paragraphs
✅ Tables for structured data
✅ References to external files for details

### Example Evaluation

**Bad (2/10):**
```markdown
When you need to create a component, it's important to first 
understand what the component should do. This involves analyzing 
the requirements carefully and thinking about how the component 
will be used. You should consider the props that will be needed, 
the state management approach, and how the component will integrate 
with the rest of the application. Once you have a clear understanding, 
you can begin writing the code.
```
Issues: Obvious advice, verbose, no examples

**Good (9/10):**
```markdown
Component creation:
1. Define props interface
2. Implement render logic
3. Add state if needed

Example:
```tsx
interface Props { name: string; }
export const Greeting = ({ name }: Props) => <div>Hello {name}</div>;
```
```
Issues: None, concise and clear

## 2. Progressive Disclosure (0-10 points)

**Principle:** Three-level system to minimize token usage.

### Scoring Rubric

**10 points - Excellent**
- YAML description < 80 chars, perfectly triggers
- SKILL.md body < 400 lines
- Details in references/ with clear navigation
- Perfect information architecture

**7-9 points - Good**
- YAML description < 100 chars, triggers well
- SKILL.md body < 500 lines
- Some details in references/
- Good information architecture

**4-6 points - Fair**
- YAML description 100-150 chars
- SKILL.md body 500-800 lines
- Minimal use of references/
- Basic information architecture

**1-3 points - Poor**
- YAML description > 150 chars
- SKILL.md body > 800 lines
- No references/ directory
- Poor information architecture

**0 points - Critical**
- YAML description > 200 chars
- SKILL.md body > 1500 lines
- Everything in one file
- No structure

### Three Levels

**Level 1 (YAML):**
- Always loaded (~30-50 tokens)
- What the skill does + when to use it
- Target: < 100 chars

**Level 2 (SKILL.md body):**
- Loaded when skill triggers
- Core workflow and instructions
- Target: < 500 lines

**Level 3 (References):**
- Loaded as needed
- Detailed documentation, examples, schemas
- Target: Clear navigation from SKILL.md

### Good Patterns

✅ Core workflow in SKILL.md
✅ Details in references/
✅ Clear "See X for Y" navigation
✅ Domain-specific content separated

### Example Evaluation

**Bad (3/10):**
```yaml
description: This skill helps you work with databases. It provides comprehensive guidance for querying, analyzing, and managing database operations across multiple database systems including PostgreSQL, MySQL, and SQLite.
```
Issues: 213 chars, too verbose

**Good (9/10):**
```yaml
description: Database query and analysis workflows. Use for: SQL queries, data analysis, schema design.
```
Issues: None, 95 chars, clear triggers

## 3. Degrees of Freedom (0-10 points)

**Principle:** Match specificity to task fragility and variability.

### Scoring Rubric

**10 points - Excellent**
- Perfect freedom level for each step
- High freedom for creative tasks
- Low freedom for fragile operations
- Clear rationale visible

**7-9 points - Good**
- Appropriate freedom for most steps
- Some mismatches
- Generally well-calibrated

**4-6 points - Fair**
- Mixed freedom levels
- Some steps too vague or too rigid
- Needs adjustment

**1-3 points - Poor**
- Inappropriate freedom levels
- Too vague or too rigid throughout
- Major calibration issues

**0 points - Critical**
- No consideration of freedom
- Either all vague or all rigid
- Unusable

### Freedom Levels

**High Freedom (text instructions):**
- Multiple valid approaches
- Context-dependent decisions
- Creative solutions encouraged

Example: "Analyze requirements and propose database schema."

**Medium Freedom (pseudocode/patterns):**
- Preferred pattern exists
- Some variation acceptable
- Guided but flexible

Example:
```
1. Parse input specification
2. For each entity: define key, attributes, relationships
3. Generate CREATE TABLE statements
```

**Low Freedom (exact scripts):**
- Fragile operations
- Consistency critical
- Specific sequence required

Example:
```bash
#!/bin/bash
psql -U $DB_USER -d $DB_NAME -f schema.sql
```

### Red Flags

❌ "Do whatever you think is best" (for fragile operations)
❌ "Use this exact code" (for creative tasks)
❌ No structure at all
❌ Overly rigid for simple tasks

### Example Evaluation

**Bad (2/10):**
```markdown
Create a beautiful, responsive, accessible website that follows 
best practices and modern design principles.
```
Issues: Too vague, no structure, unclear expectations

**Good (9/10):**
```markdown
Website creation:
1. Analyze requirements (identify key pages, features)
2. Choose framework (React for interactive, static HTML for simple)
3. Use template from templates/web-starter/
4. Implement features following patterns in references/web-patterns.md
5. Validate with scripts/validate-web.py
```
Issues: None, balanced freedom

## 4. Composability (0-10 points)

**Principle:** Work well alongside other skills.

### Scoring Rubric

**10 points - Excellent**
- Zero conflicts with other skills
- No exclusive assumptions
- Namespaced variables
- Perfect coexistence

**7-9 points - Good**
- Minimal conflicts
- Few exclusive assumptions
- Mostly compatible

**4-6 points - Fair**
- Some conflicts possible
- Some exclusive assumptions
- May interfere with others

**1-3 points - Poor**
- Many conflicts
- Assumes exclusive access
- Likely to interfere

**0 points - Critical**
- Cannot coexist with other skills
- Requires exclusive access
- Breaks other skills

### Red Flags

❌ Hardcoded file paths: `/tmp/output.txt`
❌ Global state assumptions
❌ "This is the only way to do X"
❌ Conflicts with common patterns
❌ Assumes specific environment setup

### Good Patterns

✅ Namespaced variables: `MYSKILL_OUTPUT_DIR`
✅ Asks user for paths
✅ Works with existing files
✅ Doesn't assume exclusive access
✅ Documents interactions with other skills

### Example Evaluation

**Bad (2/10):**
```markdown
Always save output to /tmp/result.txt
Set environment variable OUTPUT_DIR=/tmp/
```
Issues: Hardcoded paths, global state, conflicts likely

**Good (9/10):**
```markdown
Save output to user-specified path or ask for location.
Use environment variable ANALYSIS_OUTPUT_DIR if set, 
otherwise ask user.
```
Issues: None, flexible and composable

## 5. Portability (0-10 points)

**Principle:** Identical behavior across Claude.ai, Claude Code, API.

### Scoring Rubric

**10 points - Excellent**
- Works identically everywhere
- Dependencies clearly documented
- Fallbacks provided
- Zero platform-specific code in SKILL.md

**7-9 points - Good**
- Works on all platforms
- Dependencies documented
- Minor platform differences
- Mostly portable

**4-6 points - Fair**
- Works on most platforms
- Some dependencies undocumented
- Some platform-specific code
- Needs adjustment

**1-3 points - Poor**
- Works on one platform only
- Dependencies not documented
- Lots of platform-specific code
- Major portability issues

**0 points - Critical**
- Platform-locked
- No documentation
- Cannot work elsewhere
- Completely non-portable

### Red Flags

❌ "Only works in Claude Code"
❌ Undocumented dependencies
❌ Platform-specific code in SKILL.md
❌ No fallback options
❌ Assumes specific environment

### Good Patterns

✅ Documents all dependencies
✅ Provides fallbacks
✅ Platform-agnostic SKILL.md
✅ Scripts handle platform differences
✅ Clear environment requirements

### Example Evaluation

**Bad (2/10):**
```markdown
Use the Claude Code file browser to select files.
Run the VS Code extension command.
```
Issues: Claude Code specific, no fallbacks

**Good (9/10):**
```markdown
## File Selection

- Claude Code: Use file browser
- Claude.ai: Ask user to paste content or upload
- API: Receive file path in request

## Dependencies

- Python 3.8+ with pandas
- If pandas unavailable: Use built-in csv module (slower)
```
Issues: None, portable with fallbacks

## Overall Score Calculation

**Total Score = Sum of all 5 principles (0-50)**

### Score Interpretation

**45-50: Excellent**
- Exemplary skill
- Follows all best practices
- Ready for community distribution
- Minor tweaks only

**35-44: Good**
- Solid skill
- Follows most best practices
- Minor improvements needed
- Ready for team use

**25-34: Fair**
- Functional skill
- Some best practices followed
- Significant improvements needed
- Needs refactoring before sharing

**15-24: Poor**
- Problematic skill
- Few best practices followed
- Major improvements required
- Recommend rewrite

**0-14: Critical**
- Broken skill
- No best practices followed
- Complete rewrite required
- Start from scratch

## Weighted Scoring (Optional)

For different priorities:

**Token Efficiency Focus:**
- Concise: 30%
- Progressive Disclosure: 30%
- Degrees of Freedom: 20%
- Composability: 10%
- Portability: 10%

**Team Distribution Focus:**
- Portability: 30%
- Composability: 25%
- Progressive Disclosure: 20%
- Concise: 15%
- Degrees of Freedom: 10%

**Personal Use Focus:**
- Degrees of Freedom: 30%
- Concise: 25%
- Progressive Disclosure: 20%
- Portability: 15%
- Composability: 10%

Adjust weights based on use case.
