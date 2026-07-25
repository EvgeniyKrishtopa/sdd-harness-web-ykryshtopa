---
name: architecture-review
description: Reviews an OpenSpec design.md, or a diff, for architecture risks — boundary violations, mixed concerns, god components/services, circular dependencies, duplicated domain logic, unnecessary global state. Use right after a design.md is drafted, before committing any change touching 2+ layers, or for any high-risk change.
---

Run **Gate 1** of this project's review pipeline: architecture review.

## When invoked against a design artifact (no diff yet)

1. Read the OpenSpec change's `design.md` (or equivalent proposal doc).
2. Delegate to the `architecture-reviewer` subagent (`Agent` tool), pointing it
   at the design artifact's path — it reviews the *proposed* architecture,
   not a diff, because none exists yet at this point in the workflow.
3. Use the `sequential-thinking` MCP tool if the design is non-trivial
   (multiple layers, a new cross-cutting concern, a data-flow change) — work
   through the boundary/coupling implications step by step before handing a
   verdict to the user, rather than pattern-matching a snap judgment.

## When invoked against a diff

1. Run `git diff` (or `git diff --cached` if the target is staged) against
   the parent branch.
2. Delegate to `architecture-reviewer` with that diff.

## Handling the result

- **CONFIRMED finding** — show it to the user and ask whether to revise the
  design/diff now or proceed anyway. Do not silently continue past an
  unresolved CONFIRMED finding.
- **Clean, or PLAUSIBLE-only** — continue the workflow (artifact-creation
  loop, or straight to the next gate).

Never invent your own architecture criteria here — all of the actual review
logic lives in `architecture-reviewer`; this skill only orchestrates when it
runs and what happens with its verdict.
