# `docs/decisions/` — architecture decision records

One file per decision, `docs/decisions/NNNN-<slug>.md` (4-digit
zero-padded, sequential, kebab-case slug), ADR format. This directory does
not exist until the first decision is actually written into it —
`init-harness` doesn't pre-create it.

## Routing rule

Not every decision belongs here. The rule that keeps this directory from
either sitting empty or collecting everything:

- A decision scoped to the lifetime of one OpenSpec change — it only matters
  while that change is being built — belongs in that change's own
  `design.md`. It archives with the change when the change is archived, and
  that's fine: nothing outside that change ever needed it.
- A decision that outlives a single change — a convention, a tool choice, an
  architectural stance the *next* change will also need to know about —
  belongs here, in `docs/decisions/`.

`opsx-apply-git` applies this rule at both points a decision actually
surfaces — an autonomous isolated group (§3 Case A) and a judgement-heavy
group (§3 Case B) alike, filtered first through
`skills/opsx-apply-git/references/decision-threshold.md`'s bar. Which branch
the work happened to fall into decides the record's *state* (see States
below), never whether it gets written at all.

## If the project already has `docs/adr/`

Use that instead. Check for it before creating `docs/decisions/` for the
first time; if it exists, say so and write the decision there instead of
starting a second, competing ADR location in the same repo.

## States

Two states before a decision is superseded: **Proposed** and **Accepted**.
`opsx-apply-git`'s autonomous series (Case A) writes `Proposed` — nobody
has confirmed the decision yet, and there was no human in the loop to ask.
Everything else that writes a decision (Case B, where a human is already
discussing it live; `record-decision`, invoked directly by a human) writes
`Accepted` immediately — the confirmation already happened in the act of
recording it. See `skills/opsx-apply-git/references/decision-threshold.md`
for the bar that decides whether a decision gets recorded at all.

## Editing rule

An accepted decision is not edited. A decision that changes gets a **new**
file with `Supersedes: NNNN` pointing at the old one; the old file's
`## Status` line changes to `Superseded by NNNN`. This is also why two
branches recording two different decisions never conflict: each writes its
own new file, never edits an existing one.

The one exception: promoting a **Proposed** record to **Accepted** once a
human has reviewed it. That's the human review this state exists for, not
the edit this rule forbids — nothing else about the record changes when it
happens.

## Template

```markdown
# NNNN. <Decision title>

## Status

Accepted (YYYY-MM-DD)
<!-- or: Proposed (YYYY-MM-DD) -- written by an autonomous series, not yet
     confirmed; promote by changing this line to Accepted (YYYY-MM-DD) -->
<!-- or: Superseded by NNNN -->
<!-- if this decision replaces an earlier one: Supersedes: NNNN -->

## Context

<!-- What situation led to this decision needing to be made. -->

## Decision

<!-- What was decided, stated concretely enough to act on. -->

## Consequences

**Positive**

- <consequence>

**Negative**

- <consequence>

## Alternatives Considered

<!-- REQUIRED — do not omit even when there was one obvious answer. This
     section is the entire reason this format exists instead of a flat
     DECISIONS.md list: a plain "decision / reason" entry doesn't stop a
     future session from re-opening a question that was already closed with
     less context than the session that closed it. State what else was on
     the table and why each alternative was rejected. -->

- <alternative> — rejected because <reason>
```
