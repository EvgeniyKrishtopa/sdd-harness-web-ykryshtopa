---
name: ui-plan
description: Builds openspec/changes/<change>/ui-plan.md — the screen/states/components/value-source table for a change that touches the interface, before the scaffold stage or opsx-apply-git write any component code. Reads docs/design-system.md for state names and reusable component names instead of inventing either. Off by default; needs designSystem.enabled in .claude/harness.json — the same key as design-system, since one is meaningless without the other. Use once a change's proposal (and test-plan, if present) are settled, before scaffold — "ui-plan for <change>", "plan the UI for <change>", "план інтерфейсу для <change>".
---

Build the screen-by-screen table the scaffold stage and `opsx-apply-git`
later read before writing any component code, so a reusable component gets
named up front instead of rewritten after `code-review`'s CR-02 catches a
duplicate.

## Trigger

By change name, once its proposal (and `test-plan`, if the route has one)
are settled. Not yet called automatically by `opsx-propose-review` — that
wiring is separate work; until then, run this standalone for a change that
predates it.

## Action

1. Gate: read `designSystem` in `.claude/harness.json` first — manifest
   missing, key missing, or `enabled: false` → one line saying so, then stop.
2. Applicability: only a change that touches the interface. No user-facing
   surface (settings, data work, maintenance) → one line saying so, create
   nothing.
3. Read `docs/design-system.md`. Missing → stop and say to run
   `design-system` first; never invent tokens, state names, or components.
4. Check for a connected Figma/Pencil server (`claude mcp list`), same as
   `design-system`. Connected → pull the named node's values silently. Not
   connected → proceed from the change's description, mark the value-source
   column accordingly, ask nothing — a connection question belongs to
   `design-system`, not to a check that runs on every change.
5. Write `openspec/changes/<change>/ui-plan.md`: one row per screen, four
   columns — screen, states (named from `docs/design-system.md`, never
   invented), components (existing ones by the document's names, plus at
   most one new one per row with a one-phrase reason the existing set didn't
   cover it), value source (the machine node, or "described").
6. Cross-check against the proposal's acceptance criteria: every criterion
   with a human-visible outcome must land on at least one screen row. One
   missing → name it by requirement ID in the report; don't skip it
   silently. One-directional — a screen may show more than the spec asks,
   that's fine.
7. Cross-check against `docs/design-system.md`: every component named as
   existing must resolve to the file path the document gives it. Missing →
   the document is stale, say so and suggest re-running `design-system`;
   never build the table against a component list that's no longer real.
8. Report the table, the acceptance criteria it covers, and any findings
   from steps 6–7.

## What this skill never does

Draw or edit mockups, write or edit `docs/design-system.md`, write component
code (that's the scaffold stage and `opsx-apply-git`), or block anything —
it has no review-gate number; its findings are what it says in the report.
