# PRD -> Execution Order Plan (with Acceptance Criteria)

You are given a **large, disorganized PRD markdown** file. Your job is to convert it into a **high-level, dependency-ordered execution plan**.

## Output Requirements

- Output **ONLY markdown** (no code fences, no commentary).
- Do NOT include status/preamble text like “Created the file…”, “Saved…”, or similar.
- Do NOT mention file paths (especially `/workspace/...`) or where you wrote output.
- Do NOT include git instructions.
- Produce an ordered list of steps that breaks the PRD into **clear phases** that can later be split into bite-sized work.
- Each step must include:
  - A short title
  - 2–5 sentence description (what changes, where, why)
  - **Acceptance Criteria** as a bullet list (verifiable)
  - Explicit dependencies on earlier steps (if any)

## Ralph Constraints You MUST Respect (carry these into the plan)

- **Dependency Ordering Mindset (critical)**:
  - Order work so earlier items unblock later items.
  - Prefer: schema/data changes → backend logic → UI → aggregated/dashboard views → polish.
  - Never plan a step that depends on work that appears later.
- **Acceptance Criteria Mindset (critical)**:
  - Acceptance criteria must be **verifiable** (no “works well”, “good UX”, “handles edge cases”).
  - Each criterion should be something a coding agent can *check* (file exists, command passes, UI behavior verified).
  - **Always include** `"Typecheck passes"` as the **final** acceptance criterion for each step.
  - If a step adds/changes testable logic, include `"Tests pass"`.
  - If a step changes UI, include `"Verify in browser using browser MCP tools"` (or equivalent).

## Step Sizing Guidance (for this stage)

These steps are **higher-level** than final user stories, but still should be sensibly scoped and dependency-ordered. If something is obviously huge, break it into multiple steps here.

