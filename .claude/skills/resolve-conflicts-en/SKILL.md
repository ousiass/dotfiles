---
name: resolve-conflicts-en
description: Resolve PR conflicts safely in an isolated git worktree by specifying PR number.
user-invocable: true
---

**Language: Always interact with the user in 日本語.**

# resolve-conflicts-en

Resolve PR conflicts safely in an isolated worktree.

## Prerequisites

- Claude Code environment
- `git`, `gh` CLI

## Arguments

- **PR number** (e.g., `/resolve-conflicts-en #123` or `/resolve-conflicts-en 123`)
- **PR URL** (e.g., `/resolve-conflicts-en https://github.com/owner/repo/pull/123`)
- **No arguments**: Ask user for PR number

## Phase 1: Retrieve PR Info and Create Worktree

1. Identify the PR from arguments
   - `gh pr view <number-or-URL> --json number,title,baseRefName,headRefName,headRepository,headRepositoryOwner,mergeable,url`
   - No arguments: Ask user for PR number
2. Display and confirm PR info
   - PR title, base branch, head branch, conflict status
   - If mergeable is not `CONFLICTING`: Report no conflicts and exit
3. Record base branch and head branch
4. Confirm resolution strategy with user (AskUserQuestion)
   - **rebase** (recommended): Rebase head branch onto base branch. Clean history. Requires `--force-with-lease` on push
   - **merge**: Merge base branch into head branch. Adds a merge commit. Regular push
5. **Create git worktree** (see `references/worktree-setup.md`)
   - Branch name: `resolve/<PR-number>` (e.g., `resolve/#123`)
   - After worktree creation, checkout head branch content:
     ```bash
     cd <worktree-path>
     git fetch origin
     git reset --hard origin/<head-branch>
     ```

## Phase 2: Resolve Conflicts

**IMPORTANT: All operations must be inside the worktree directory.**

### Rebase Strategy

1. Start rebase inside worktree
   ```bash
   git rebase origin/<base-branch>
   ```
2. Check conflicting files
   ```bash
   git diff --name-only --diff-filter=U
   ```
3. **For each conflicting file:**
   a. Read the full file with Read (including conflict markers)
   b. Understand base branch change intent (`git log origin/<base-branch> -- <file>` for recent changes)
   c. Understand head branch change intent (`git log HEAD -- <file>` for recent changes)
   d. Resolve by preserving both change intents. Ask user when uncertain
   e. Resolve conflict markers with Edit
   f. Stage with `git add <file>`
4. After all conflicts resolved:
   ```bash
   git rebase --continue
   ```
5. If new conflicts arise, repeat steps 2-4
6. Repeat until rebase is complete

### Merge Strategy

1. Start merge inside worktree
   ```bash
   git merge origin/<base-branch>
   ```
2. Check conflicting files (same as rebase steps 2-3)
3. Resolve each conflict (same as rebase steps 3a-3f)
4. After all conflicts resolved:
   ```bash
   git add .
   git commit  # Create merge commit
   ```

### Resolution Guidelines

- **Preserve both changes**: Integrate both sides whenever possible
- **Prioritize intent**: Understand change intent, not just line-level differences
- **Ask user when uncertain**: Always ask when business logic judgment is needed
- **Run tests/type checks**: Verify tests and type checks pass after resolution

## Phase 3: Verify and Push

1. **Run build/tests** (inside worktree directory)
   - Run test command if project has one
   - If failures, fix and commit
2. **Push** (inside worktree directory)
   - Rebase strategy: `git push origin HEAD:<head-branch> --force-with-lease`
   - Merge strategy: `git push origin HEAD:<head-branch>`
3. Confirm PR conflict status
   - Verify MERGEABLE with `gh pr view <number> --json mergeable`
4. Report resolution summary and **worktree path** to user

Report example:
```
## Done
- PR: <URL>
- Strategy: rebase / merge
- Resolved files: N
  - path/to/file1.ts: Integrated both changes
  - path/to/file2.ts: Added new imports from base
- Worktree: <path> (run `git worktree remove <path>` after verification)
```

## Rules

- Make no changes beyond conflict resolution
- Ask user when business logic judgment is needed
- Use `--force-with-lease` to avoid overwriting others' commits
- **All git/file operations must be inside the worktree directory. Never modify the main working tree.**
- Get user confirmation before pushing (especially for rebase + force push)
