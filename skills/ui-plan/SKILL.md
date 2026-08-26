---
name: ui-plan
description: Builds openspec/changes/<change>/ui-plan.md — the screen/states/components/value-source table for a change that touches the interface, before the scaffold stage or opsx-apply-git write any component code. Reads docs/design-system.md for state names and reusable component names instead of inventing either. Off by default; needs designSystem.enabled in .claude/harness.json — the same key as design-system, since one is meaningless without the other. Use once a change's proposal (and test-plan, if it already has one) are settled, before scaffold — "ui-plan for <change>", "plan the UI for <change>", "план интерфейса для <change>".
---

Build the screen-by-screen table the scaffold stage and `opsx-apply-git`
later read before writing any component code, so a reusable component gets
named up front instead of rewritten after `code-review`'s CR-02 catches a
duplicate.

## Trigger

By change name, once its proposal (and `test-plan`, if it already has one)
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
4. Per screen with a mockup link in the change's own materials and a
   connected Figma/Pencil server (`claude mcp list`): pull that link's node
   values silently. No link, or no connected server → proceed from the
   change's description, mark the value-source column accordingly — ask
   nothing, a connection question belongs to `design-system`, not here.
5. Pick each screen's components before writing anything: existing ones by
   the document's names, plus at most one new one per screen with a
   one-phrase reason. Every existing name must resolve to the file path
   `docs/design-system.md` gives it — one that doesn't → the document is
   stale (compare its recorded Commit line to the current one), say so and
   suggest re-running `design-system`, and stop before writing the table.
6. Write `openspec/changes/<change>/ui-plan.md`: one row per screen, four
   columns — screen, states (named from `docs/design-system.md`, never
   invented), the components step 5 picked, value source (the mockup node,
   or "described").
7. Cross-check against the proposal's acceptance criteria: every criterion
   with a human-visible outcome must land on at least one screen row. One
   missing → name it by requirement ID; don't skip it silently.
   One-directional — a screen may show more than the spec asks, that's fine.
   Report the table, the criteria it covers, and any gap found here.

## What this skill never does

Draw or edit mockups, write or edit `docs/design-system.md`, write
component code (that's the scaffold stage and `opsx-apply-git`), or block
anything — no review-gate number; its findings are only what it reports.
