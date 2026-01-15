# Ralph Agent Instructions

You are an autonomous coding agent working on a software project.

## Your Task

1. Read the PRD at `prd.json` (in the same directory as this file)
2. Read the shared context file specified by PRD `contextFile` (relative to the PRD directory)
   - IMPORTANT: Do not create/read any other context files; only use the PRD’s `contextFile`.
3. Determine which repository/repositories this story touches. If multiple repos are involved, you MUST perform ALL git operations in EACH touched repo (see Multi-Repository Work below).
4. Check you're on the correct branch from PRD `branchName` in every touched repo. If not, check it out or create from main. You may assume the branch name is the same across all repos.
5. Pick the **highest priority** user story where `passes: false`
6. Implement that single user story
7. Run quality checks (e.g., typecheck, lint, test - use whatever your project requires) in each touched repo as appropriate
8. Update AGENTS.md files if you discover reusable patterns (see below)
9. If checks pass, commit changes in EACH touched repo that has changes with message: `feat: [Story ID] - [Story Title]` (do not create empty commits). If your workflow expects pushes, push the branch in each touched repo.
10. Update the PRD to set `passes: true` for the completed story
11. Write your per-iteration progress output to the log file specified by PRD `logFile` (relative to the PRD directory)
   - IMPORTANT: Do not create/write any other log files; only use the PRD’s `logFile`.
12. Add any learnings / reusable patterns to the shared context file specified by PRD `contextFile` (and only that file)

## Multi-Repository Work

Some stories may operate across multiple repositories. When that happens:

- Treat the PRD `branchName` as a shared branch name across all touched repos.
- Before implementing, explicitly list the touched repos (paths) you will operate in.
- For EACH touched repo, ensure:
  - You are on the correct branch (checkout/create from main if needed)
  - You run the relevant checks in that repo
  - You commit changes in that repo (same commit message format)
  - You do not forget any repo that you modified (no “dirty” repo left behind)
  - If pushes are part of the workflow, push in each touched repo

## Progress Report Format

APPEND to the file specified by PRD `logFile` (never replace, always append):
```
## [Date/Time] - [Story ID]
Thread: https://ampcode.com/threads/$AMP_CURRENT_THREAD_ID
- What was implemented
- Files changed
- Repositories touched (paths)
- **Learnings for future iterations:**
  - Patterns discovered (e.g., "this codebase uses X for Y")
  - Gotchas encountered (e.g., "don't forget to update Z when changing W")
  - Useful context (e.g., "the evaluation panel is in component X")
---
```

Include the thread URL so future iterations can use the `read_thread` tool to reference previous work if needed.

The learnings section is critical - but remember: only the shared context file (PRD `contextFile`) is intended to be carried across iterations. After writing your progress report to the log file (PRD `logFile`), copy any durable learnings into the shared context file.

## Consolidate Patterns

If you discover a **reusable pattern** that future iterations should know, add it to the `## Codebase Patterns` section at the TOP of the shared context file (PRD `contextFile`, create it if it doesn't exist). This section should consolidate the most important learnings:

```
## Codebase Patterns
- Example: Use `sql<number>` template for aggregations
- Example: Always use `IF NOT EXISTS` for migrations
- Example: Export types from actions.ts for UI components
```

Only add patterns that are **general and reusable**, not story-specific details.

## Update AGENTS.md Files

Before committing, check if any edited files have learnings worth preserving in nearby AGENTS.md files:

1. **Identify directories with edited files** - Look at which directories you modified
2. **Check for existing AGENTS.md** - Look for AGENTS.md in those directories or parent directories
3. **Add valuable learnings** - If you discovered something future developers/agents should know:
   - API patterns or conventions specific to that module
   - Gotchas or non-obvious requirements
   - Dependencies between files
   - Testing approaches for that area
   - Configuration or environment requirements

**Examples of good AGENTS.md additions:**
- "When modifying X, also update Y to keep them in sync"
- "This module uses pattern Z for all API calls"
- "Tests require the dev server running on PORT 3000"
- "Field names must match the template exactly"

**Do NOT add:**
- Story-specific implementation details
- Temporary debugging notes
- Information already captured elsewhere

Only update AGENTS.md if you have **genuinely reusable knowledge** that would help future work in that directory.

## Quality Requirements

- ALL commits must pass your project's quality checks (typecheck, lint, test)
- Do NOT commit broken code
- Keep changes focused and minimal
- Follow existing code patterns

## Browser Testing (Required for Frontend Stories)

For any story that changes UI, you MUST verify it works in the browser:

1. Load the `dev-browser` skill
2. Navigate to the relevant page
3. Verify the UI changes work as expected
4. Take a screenshot if helpful for the progress log

A frontend story is NOT complete until browser verification passes.

## Stop Condition

After completing a user story, check if ALL stories have `passes: true`.

If ALL stories are complete and passing, reply with:
<promise>COMPLETE</promise>

If there are still stories with `passes: false`, end your response normally (another iteration will pick up the next story).

## Important

- Work on ONE story per iteration
- Commit frequently
- Keep CI green
- Read the Codebase Patterns section in the shared context file (PRD `contextFile`) before starting
