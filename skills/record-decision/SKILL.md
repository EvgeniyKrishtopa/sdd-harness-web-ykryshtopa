---
name: record-decision
description: Records an architecture or convention decision reached outside the normal review flow — in chat, a meeting, a whiteboard, or directly in code — as an Accepted entry in docs/decisions/ (or docs/adr/ if the project already has one). Use when a decision is already settled and just needs to be written down, e.g. "we decided to use X for Y", "write down that we're doing Z", "record this decision".
---

Write down a decision nobody captured at the point it was actually made.

## Trigger

The user describes a decision that's already settled, reached somewhere
this pipeline wasn't watching, and asks to have it recorded — or you
notice one mid-conversation and it isn't written anywhere yet. This is
**not** the normal path: a decision surfacing inside `opsx-apply-git`
(`skills/opsx-apply-git/references/decision-threshold.md` covers both its
cases) is recorded by that skill instead, since a human is already in the
loop by construction there. Reach for this skill only when nothing else in
the pipeline was present when the decision was actually made.

## Action

1. Confirm the decision crosses the same bar
   `decision-threshold.md` uses: irreversible or expensive to reverse,
   touches more than one module, or had live alternatives someone could
   reasonably have picked instead. If it doesn't cross that bar, say so and
   suggest a lighter trace — a code comment, a line in the relevant
   `design.md` — rather than creating a permanent record for something
   trivial.
2. Gather, in plain conversation, what
   `skills/init-harness/references/decision-template.md`'s template needs:
   the context that led to it, the decision stated concretely enough to
   act on, its consequences (positive and negative), and — required, never
   skip — the alternatives that were on the table and why each was passed
   over.
3. Check for an existing `docs/adr/` first; if the project already has
   one, write there instead of starting a second, competing location.
4. Write `docs/decisions/NNNN-<slug>.md` (or the `docs/adr/` equivalent)
   with the next sequential number, `## Status` set to **Accepted** — the
   user is confirming this decision in the act of asking for it to be
   recorded, so it never starts as Proposed.
5. Report the file path and number.

## What this skill never does

Never edit an existing decision file — the same edit discipline
`decision-template.md` states applies here exactly as it does to
`opsx-apply-git`'s own writes. A decision that changes gets a new file
with `Supersedes: NNNN`, not a rewrite of the old one.
