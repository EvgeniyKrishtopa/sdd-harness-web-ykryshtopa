---
name: design-system
description: Writes docs/design-system.md — the project's one design record (basis, design tokens, UI primitives, state names, source) that ui-plan and the scaffold stage read instead of each guessing UI details on their own. Two entry modes chosen automatically — a short Q&A on an empty project, or extraction from an already-written UI on one that has it. Off by default; needs designSystem.enabled in .claude/harness.json. Manual, once per project and again after a notable UI change — never runs on its own from a feature flow. Use for "design system for this project", "set up the design system", "extract the design system from the code", or in Russian "дизайн-система проекта", "собери дизайн-систему", "вытащи дизайн-систему из кода".
---

Write the one document later UI-aware steps (`ui-plan`, once it exists; the
scaffold stage) read instead of guessing UI details per feature — they stop
and point here when it's missing rather than doing this work themselves.
Gate: read `designSystem` in `.claude/harness.json` first — manifest
missing, key missing, or `enabled: false` → one line saying so, then stop.

## Pick the entry mode

Look for a components folder, style files, or markup already in the repo.

- **Almost none of that** → from scratch. Ask, one at a time via
  `AskUserQuestion`, at most these four, each with a default:
  1. Ready-made primitive library as the base, or build our own? Default:
     ready-made (a homegrown one in week one is a separate project).
  2. Four meaningful colors — primary, danger, success, muted? Default: the
     chosen library's own theme role for each.
  3. Spacing step and text-size step? Default: whatever the library ships.
  4. Where should primitives/styling values live? Default: alongside other
     shared UI code (e.g. `src/components`).
- **UI already written** → extract from code. Record what's actually there:
  existing components (name, what it is), repeated colors/spacing and
  whether they're named, and every place the same thing is done two ways
  (two button variants, three spacings for one slot). List discrepancies for
  the human; **never fix them** — that's a UI change with its own spec.
  Never invent a name that isn't in the code. Both modes write the same
  document — five sections, see `references/document-template.md`.

## External design tool

Free check: `claude mcp list`, look for a connected server named like Figma or Pencil.

- **Connected** → use its values silently, no questions; name the tool in the document's source section.
- **Not connected, existing doc's Source line not already marked "skipped"**
  → one `AskUserQuestion`: connect Figma / connect Pencil / skip and write
  from description. A tool choice gets connection steps *shown*, never run
  — then check again. Still not visible → say a new server usually needs a
  restart, and offer continue now from description, or stop and return
  after restarting.
- **Skip, or already marked "skipped"** → write from description; Source
  line reads exactly `non-machine — skipped connecting a tool` (the marker
  the check above looks for), plus one report line on a fresh skip that
  connecting a server lets the next run pull real values.

## Never

Draw mockups, write stylesheets or tokens into code (records decisions;
values come from the library or the tool), fix a discrepancy it finds, run
itself from a feature's flow, or impose a house style of its own.
