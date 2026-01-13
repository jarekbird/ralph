# PRD -> Shared Context Extraction

You are extracting **shared context** that will be reused across many iterations of implementation.

## Output Requirements

- Output **ONLY markdown** (no code fences, no commentary).
- Keep it **as concise as possible**, but include all stable shared context needed across steps.
- Prefer **facts and decisions** over prose.
- Do NOT include step-by-step instructions (those belong in the steps file).

## Required Structure

Use this structure (keep headings exactly):

```
# Ralph Context

## Codebase Patterns
- (Only reusable patterns/conventions; omit story-specific details)

## Domain / Product Context
- (Key terms, definitions, entities, rules)

## Technical Constraints
- (Performance, security, compatibility, dependencies)

## Notes
- (Only stable notes that multiple steps will need)
```

## Ralph Memory Model (Important)

- This file is the **durable shared context** across iterations.
- Avoid anything that would be useful only once or that is a progress log.

