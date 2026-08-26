# `docs/design-system.md` — the five sections

Same shape whether written from scratch or extracted from existing code — a
reader shouldn't be able to tell which entry mode produced it. Write real
values only; where a value wasn't found (no name, no answer given), say so
in the document instead of inventing one.

```markdown
# Design system

## 1. Basis

<!-- Own primitives, or a named ready-made library (and which one). -->

## 2. Design tokens

<!-- Four meaningful color roles — primary, danger, success, muted — plus
     the spacing step and the text-size step. Each with the name it's kept
     under in the code (a CSS variable, a theme key, a Tailwind token). A
     role with no name yet: say so, don't invent one. -->

| Role | Value | Name in code |
| --- | --- | --- |
| primary | | |
| danger | | |
| success | | |
| muted | | |
| spacing step | | |
| text-size step | | |

## 3. UI primitives

<!-- One row per primitive that already exists (from-scratch: what the
     chosen library ships; extracted: what the scan found). -->

| Name | What it is | Where it lives |
| --- | --- | --- |

## 4. States

<!-- Loading, error, empty, offline — under whatever names this project
     actually uses for them. This is meant to become the list the browser
     check (web-qa) reads instead of its own fallback names, so a name here
     must match the name in the code exactly, not just describe it. -->

| State | Name in this project | What it looks like |
| --- | --- | --- |
| loading | | |
| error | | |
| empty | | |
| offline | | |

## 5. Source

<!-- Machine source: which tool (Figma / Pencil) and, ideally, the file or
     project it read from. Non-machine source: say plainly that this was
     written from description, not read from a design file.
     Either way: the commit this document was taken at — the fact ui-plan
     needs to tell a current document from a stale one. -->

- Source:
- Commit: `<git rev-parse HEAD, short>`
```

## Extraction-mode discrepancies

When the extract-from-code entry finds the same thing done two different
ways, it does not fit any of the five sections above — the sections record
what the system *is*, and a discrepancy is exactly the case where the
project has no single answer yet. List these separately, in the report back
to the human, not inside the document:

```
Found 2 button styles: `Button` (src/ui/Button.tsx) and `PrimaryButton`
(src/features/checkout/PrimaryButton.tsx). Not fixed — pick one and update
this document, or open it as its own change.
```
