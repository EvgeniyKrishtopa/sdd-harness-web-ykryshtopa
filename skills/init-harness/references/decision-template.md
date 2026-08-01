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

`opsx-apply-git` applies this rule at the point decisions actually surface:
a judgement-heavy group (§3 Case B), where a human is already in the loop for
exactly this kind of call.

## If the project already has `docs/adr/`

Use that instead. Check for it before creating `docs/decisions/` for the
first time; if it exists, say so and write the decision there instead of
starting a second, competing ADR location in the same repo.

## Editing rule

An accepted decision is not edited. A decision that changes gets a **new**
file with `Supersedes: NNNN` pointing at the old one; the old file's
`## Status` line changes to `Superseded by NNNN`. This is also why two
branches recording two different decisions never conflict: each writes its
own new file, never edits an existing one.

## Template

```markdown
# NNNN. <Decision title>

## Status

Accepted (YYYY-MM-DD)
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
