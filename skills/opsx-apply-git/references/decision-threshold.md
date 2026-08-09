# Decision threshold — when a surfaced decision gets recorded, and how

Read this whenever a design decision surfaces during §3, in either case
below. It does not change when a run stops for genuine ambiguity (§3 Case A
step 2, Case B step 2) — that's a separate, unaffected trigger.

## The bar

Record it if at least one of these is true:

- irreversible, or expensive to reverse;
- touches more than one module;
- had live alternatives someone could reasonably have picked instead.

Below all three: just make the call and continue, exactly as before this
version — no file, no pause.

## Case A (isolated, autonomous) — record and continue, never stop for this alone

A decision the agent genuinely can't make confidently still means the
group was misclassified — stop, per §3 Case A step 2, unchanged. A
decision it CAN make confidently but that crosses the bar above is
different: write it up and keep the group moving, no pause, no question.
`## Status`: **Proposed** (`decision-template.md`) — nobody has confirmed
it yet; that happens later, at review time (a human reading this run's PR,
or `architecture-review`'s own new decisions step).

## Case B (judgement-heavy, human in the loop) — record what crosses the bar, straight to Accepted

Same bar, but the human is already discussing this decision live (§3 Case
B step 2's pause-and-ask), so record it directly as **Accepted** — no
separate confirmation step, the confirmation already happened in
conversation. A decision below the bar still gets no file even with a
human present; the loop shouldn't record trivia just because someone's
watching.

## Routing: which file gets the record

Unchanged from before this version — the bar above is a new filter in
front of it, not a replacement:

- Scoped to this change's own lifetime (only this change will ever need it
  again) → note it in the change's own `design.md`; it archives with the
  change.
- Outlives the change (a convention, a tool choice, a stance the *next*
  change will also need) → write it as a new `docs/decisions/NNNN-<slug>.md`
  per
  `${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/decision-template.md`,
  including its required `Alternatives Considered` section. Check for an
  existing `docs/adr/` first — if the project already has one, use that
  instead of creating `docs/decisions/` alongside it, and say so.
