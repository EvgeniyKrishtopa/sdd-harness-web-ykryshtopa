---
name: spec-review
description: Reviews a complete OpenSpec change (proposal, design, specs, tasks) for internal consistency, testable requirements, and traceability, and classifies each task group in tasks.md as isolated or judgement-heavy. Use after the full artifact set is drafted, before implementing or archiving a change.
---

Run **Gate 2** of this project's review pipeline: spec review.

## Trigger

Every artifact required by the OpenSpec schema is `status: "done"` (for the
`spec-driven` schema: proposal + design + specs + tasks all complete).

## Action

1. Delegate to the `spec-reviewer` subagent (`Agent` tool) for the whole
   change.
2. Beyond surfacing gaps, this is also where **task-group classification**
   happens: the reviewer marks each `## N.` heading in `tasks.md` as
   `isolated` or `judgement-heavy`, written back as a trailing
   `<!-- isolated -->` / `<!-- judgement-heavy -->` HTML comment on the
   heading. This classification is independent of findings — record it even
   on an otherwise clean review — and it is what `opsx-apply-git` reads to
   decide how far it can proceed autonomously. An unmarked group is treated
   as `judgement-heavy` downstream — never let a group run unattended if
   nobody classified it.
3. If the change is non-trivial (many groups, cross-cutting groups), use the
   `sequential-thinking` MCP tool to work through the isolated vs
   judgement-heavy call per group explicitly, rather than eyeballing it.

## Handling the result

- **CONFIRMED finding** — show it to the user and ask whether to revise the
  relevant artifact(s) before declaring the change ready for implementation.
- **Clean, or PLAUSIBLE-only** — declare the change ready for implementation.
  The classification is still recorded either way.
