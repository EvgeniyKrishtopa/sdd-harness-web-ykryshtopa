# Reading ui-plan.md before writing a component

Read this whenever this run's group(s) touch the interface — per
`tasks.md`'s own description: it builds or edits a screen, page, or UI
component file, or a sub-task names a screen `ui-plan.md`'s table also
names. A group that doesn't touch the interface skips this file entirely.

## What to do

Read `openspec/changes/<change>/ui-plan.md` before writing any component's
code, not after.

- Reuse each screen's existing components by the names `ui-plan.md` gives
  them from `docs/design-system.md`.
- Write a new component only where its row explicitly names one as new —
  never invent one `ui-plan.md` doesn't call for.
- For a **new** component whose row's value-source column names a machine
  source (a Figma/Pencil node): before writing its code, read that node's
  variables from the connected server (color, spacing, font) — not only the
  system tokens in `docs/design-system.md`. No node, or no connected server
  → as before: system tokens plus the row's text description.

## Fallback

Missing `ui-plan.md`, or a group that doesn't touch the interface → as
before, no `ui-plan.md` input.
