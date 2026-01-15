# Execution Order -> Bite-Sized Steps (with Acceptance Criteria)

You are given:
- A PRD markdown file
- A high-level execution-order plan
- A shared context file

Your job is to produce a `.steps.md` file: an **ordered list of bite-sized steps** that can be implemented incrementally.

## Output Requirements

- Output **ONLY markdown** (no code fences, no commentary).
- Do NOT include status/preamble text like “Created the file…”, “Saved…”, or similar.
- Do NOT mention file paths (especially `/workspace/...`) or where you wrote output.
- Do NOT include git instructions.
- Each step must be describable in **a few sentences** (2–5).
- Each step must be **small enough to complete in one Ralph iteration** (one context window).
- Each step must include:
  - Step number
  - Title
  - Short description
  - Dependencies (if any)
  - **Acceptance Criteria** (verifiable)

## Ralph Constraints You MUST Apply

- **Dependency Ordering Mindset (critical)**:
  - Order steps so earlier steps unblock later ones.
  - Prefer: schema/data → backend → UI → aggregated/dashboard → polish.
  - No step may depend on a later step.
- **Acceptance Criteria Mindset (critical)**:
  - Acceptance criteria must be **verifiable** (no vague “works well”, “good UX”, “handles edge cases”).
  - Use concrete checks: “migration runs”, “typecheck passes”, “API returns X”, “UI shows Y”.
  - **Always include** `"Typecheck passes"` as the **final** acceptance criterion for every step.
  - For steps that add/modify testable logic: include `"Tests pass"`.
  - For steps that change UI: include `"Verify in browser using browser MCP tools"` as a final criterion.

## Notes

- If the PRD includes multi-repo work, ensure the steps make that explicit where relevant.
- Prefer 1 “unit” of change per step (one migration, one endpoint, one component, one behavior).

