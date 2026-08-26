---
name: opsx-scaffold
description: Turns an OpenSpec change's already-approved design.md boundaries into real files at their final paths — typed signatures and stub bodies, no logic — confirms the file map with the human in one question, then commits it as its own branch before any feature code is written. Runs only when the proposal step's two observable questions (new module? new boundary crossing?) said yes and `.claude/harness.json` has scaffolding enabled; every other change skips it silently and goes straight to `opsx-apply-git`. Use for "каркас для {change}", "структура файлов {change}", "утверди карту каркаса", or in English "scaffold {change}", "file map for {change}", "confirm the scaffold structure".
---

Turn a change's approved architecture into files before its logic gets
written, so implementation fills in a structure the human already signed off
on instead of inventing its own.

## What this stage does not do

It does not re-open the architecture. That was already decided in `design.md`
and at Gate 1 (`architecture-review`). The only question this stage asks the
human is "is this file map correct?" — never "is this the right design?". If
writing this stage tempts a second architecture conversation on a
neighboring step, that step is scoped wrong.

## Steps

0. Select the change (explicit name, inferred from conversation, or ask via
   `AskUserQuestion` if ambiguous) — the same first move `opsx-apply-git`
   and `opsx-update-review` make before touching a change's files. Then read
   `.claude/docs/git-conventions.md` and `.claude/harness.json` — the same
   first read `opsx-apply-git` does in its own steps 0-1. Manifest missing →
   stop and send the human to `init-harness` first.
1. Read the `scaffold` key in `.claude/harness.json` — before anything else
   below. Key missing, or `enabled: false` → say in one line that this repo
   hasn't turned the stage on, name `opsx-apply-git` as the next skill, and
   stop. An unconfigured or disabled repo never gets this stage sprung on it
   unannounced, regardless of what any individual change's own marker says.
2. Read `openspec/changes/<change>/.scaffold`. First line `no` → say in one
   line that this change doesn't need a scaffold, name `opsx-apply-git` as
   the next skill, and stop. File missing entirely (an older change, or a
   repo still on a plugin version before this one) → treat it as `no`.
   Never infer on your own that a change needs a scaffold just because the
   marker is absent.
3. Read this change's `design.md` (boundaries, module composition, sequence
   diagrams) and the spec files listed under `contextFiles`
   (`openspec instructions apply --change "<name>" --json`). Read `tasks.md`
   too — required: the file map below must cover exactly the files the
   tasks are about to touch, and nothing beyond them.
4. Draw the file map: path, responsibility, export. Take paths from this
   project's own conventions — how its existing modules are actually laid
   out — never from a generic framework template; this stage does not know
   what "a typical page" looks like and must not guess. First check for
   `openspec/changes/<change>/ui-plan.md` — present → read its
   screen/components table before drawing the map, so a screen that reuses
   an existing component doesn't get scaffolded a new file for it, and only
   the components the table actually marks as new get one. Missing → draw
   the map as before, with no UI-plan input.
5. Show the map to the human and ask exactly **one** `AskUserQuestion`:
   approve it, or fix it. A fix is discussed in conversation, and the map is
   shown again after each change. Ask nothing about the architecture here —
   see "What this stage does not do" above.
6. Once approved, create the files. Content rules: "What a scaffold is",
   below.
7. Run typecheck and lint using `scripts.typecheck` and `scripts.lint` from
   the manifest. A failure gets fixed in the scaffold, never waved off by
   loosening the check. The project's existing test suite must stay green —
   this stage adds no tests of its own.
8. **Run the scaffold review — Gate 2b.** Read `.claude/harness.json`'s
   `models.architecture` key and pass it as the `model` override, the same
   way `architecture-review` does; missing manifest or key → the agent's own
   default, never a reason to stop. Check for a decisions folder the same
   way `architecture-review` does — `docs/adr/` first, then
   `docs/decisions/`, a 0-token `test -d` — and pass whichever exists.
   Delegate to the `architecture-reviewer` subagent (`Agent` tool) in its
   scaffold-review mode, handing it: this branch's diff against its parent
   branch, `design.md` (including its sequence diagrams), `tasks.md`, and
   the decisions-folder path if one exists. Also pass the manifest's
   `disabledRules` array as context, the same way `architecture-review`
   does — an empty or missing array disables nothing.
   - **CONFIRMED finding** — show it to the human and ask whether to fix the
     scaffold now or continue anyway. Do not silently continue past an
     unresolved CONFIRMED finding. A fix lands as its own commit on this
     same scaffold branch — this stage's one-commit shape from step 11
     below still holds for the scaffold itself; a fix commit added after
     review is expected, not an exception to it.
   - **Clean, or PLAUSIBLE-only** — continue to the next step.
   Then append one line to `.claude/harness-log.jsonl` (create it if
   missing), the same shape every other gate's line uses — see
   `skills/architecture-review/SKILL.md`'s own logging step for the exact
   `jq` command and field meanings — with `gate: "scaffold-review"` and
   `group` carrying this change's route: `openspec/changes/<change>/.route`'s
   first line, `short` or `full`; missing → treat as `full`, the same rule
   `architecture-review` uses (this gate runs at change scope, not per task
   group). `fixIterations`/`escalatedToHuman` are always `0`/`false`: a
   CONFIRMED finding here is fixed by hand in conversation, not by
   `debug-loop`.
9. Append the "Scaffold map" section to `design.md` — see below.
10. If the human rejected a real alternative during step 5's conversation,
    record it through the existing decision threshold
    (`skills/opsx-apply-git/references/decision-threshold.md`). No rejected
    alternative → write nothing; a decision record for every single
    scaffold is not the goal.
11. Branch `feature/<change>-scaffold` off the change's own parent branch,
    one commit `scaffold(<change>): <short summary>` (plus the review's fix
    commit from step 8, if there was one), open a merge request into the
    parent. The human merges it. Once merged, the parent branch already
    contains the scaffold, and the change's first task group builds on top
    of it rather than inventing structure of its own.
12. Report: how many files were created, where the map was written, the
    scaffold review's verdict, whether a decision was recorded, and that
    `opsx-apply-git` is the next skill to run.

## What a scaffold is

A scaffold is real files at their final paths, with types and function
signatures, and no bodies.

**Must be inside:**

- files at the paths the feature will actually live at;
- the data types the feature moves between layers, with their fields;
- signatures for every exported function and component: name, parameters,
  return type;
- stub bodies only: `throw new Error('not implemented')` for a function, a
  `null` return for a component.

**Must not be inside:**

- any business logic, even a single line;
- any markup or styling;
- any data loading, real or fake;
- any invented display data;
- any new dependency;
- any schema migration;
- any file that no task in `tasks.md` actually mentions.

**Why signatures, not empty files.** An empty file has nothing to check
against — typecheck passes on emptiness for free, there are no tests yet,
and a reviewer is left staring at a folder tree with nothing to say beyond
"looks fine." Types and signatures give three real things: typecheck
actually checks something; a mismatch against the sequence diagrams becomes
visible before any logic is written (a diagram shows an error branch a
signature's return type doesn't account for); and implementation gets a
contract to satisfy, not just an empty folder to fill however it likes.

## Scaffold map

Step 9 appends a section to `design.md`, titled `## Scaffold map`, a
three-column table:

```
| File | Responsibility | Exports |
| --- | --- | --- |
| path/to/file.ts | what it's responsible for | name, name |
```

Real paths, real exports — write this section **after** the files exist
(step 6), never before, so it describes what is actually on disk rather than
what was planned. No new document: this is a section of the change's
existing `design.md`, not a new file under the change's own folder.

**What goes in the map vs. what goes in a decision record.** The same
conversation (step 5) can produce both, and they are not the same thing.
If the human rejected a real alternative out loud — "modules by feature, not
a shared components folder" — that's a decision; it had a live alternative
someone could have picked instead, and step 10 above is what records it. If
the answer was simply where something landed — "the cart lives in
`features/cart`, only `api.ts` is exported outward" — that's a fact about
the code, and it belongs in this map, not in a decision record. Never write
a decision record for a scaffold that had no rejected alternative — most
scaffolds won't have one, and that's the expected case, not a gap.
