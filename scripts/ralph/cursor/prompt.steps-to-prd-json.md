# Steps -> prd.json (Ralph)

You are converting a `.steps.md` file into a `prd.json` file used by the Ralph autonomous agent system.

## Story Size: The Number One Rule (Critical)

Each story MUST be completable in **one** Ralph iteration (one context window).

- If a step is too large to complete in one iteration, you MUST split it into multiple `userStories`.
- Rule of thumb: if the story cannot be described in 2–3 sentences, it is too big.

## Output Requirements (Critical)

- Output **ONLY valid JSON**.
- Do NOT include code fences.
- Do NOT include commentary or trailing notes.

## prd.json Format

Follow the schema shown in the provided `prd.json.example` reference.

## Conversion Rules (MUST)

1. Each step becomes **one** `userStories[]` entry.
2. **IDs**: sequential: `US-001`, `US-002`, ...
3. **priority**: sequential (1..N) in dependency order.
4. **passes**: always `false` initially.
5. **notes**: always `""` initially.
6. **acceptanceCriteria**:
   - Must be verifiable.
   - Must include `"Typecheck passes"` as the **final** criterion for every story.
   - If story changes UI, include `"Verify in browser using browser MCP tools"` as a final criterion (after typecheck is OK too, but keep typecheck present).
   - If story adds/changes testable logic, include `"Tests pass"`.
7. **branchName**: `ralph/<feature-name-kebab-case>` derived from the input PRD file name or PRD title.
8. **contextFile**:
   - MUST be set to `<same-base>.context.md` (same base name as the PRD/steps).
   - Do NOT use a shared `context.md` unless it is explicitly the same-base file.
9. **logFile**:
   - MUST be set to `<same-base>.progress.log` (same base name as the PRD/steps).
   - Do NOT use a shared `progress.log` unless it is explicitly the same-base file.
10. **description**: derived from PRD title/intro (1 sentence).
11. **project**: use the product/app name if present; otherwise use the repository/project name if implied; otherwise fall back to `"MyApp"` (matching the example).

