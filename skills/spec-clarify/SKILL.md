---
name: spec-clarify
description: Sweeps a drafted OpenSpec change for ambiguous wording — spots where two engineers would reasonably build different things — and resolves every finding with the user, either by editing the spec on the spot or logging it under Open Questions with an owner and due date. Use between drafting a change's artifacts and spec review, or again after any artifact is revised. Triggers include "clarify this change", "find ambiguities in <change>", "sweep for ambiguity", "resolve open questions".
---

Close every ambiguity a change's drafted artifacts still carry before the
change moves on to `spec-review` (Gate 2). `spec-review` checks the document
is internally correct; this checks that it actually decided things — see
`agents/devils-advocate.md` for what counts as an undecided spot, and
`harness-audit/v0.5.0-planned/06-design-rationale.txt` decisions 2-4 for why
finding ambiguity and resolving it are two separate steps rather than one.

## Trigger

Called by `opsx-propose-review`, between its artifact-generation step and its
`spec-review` step, once every artifact is `status: "done"`. Called again by
`opsx-update-review` whenever a revision touches any artifact — a fix to one
ambiguity can introduce another, so a change that's been edited is swept
again rather than trusted from its first pass.

## Action

1. Identify the change (the caller names it; if invoked standalone and it's
   ambiguous which change, confirm with the user via `AskUserQuestion`, the
   same pattern `opsx-update-review` step 1 uses).
2. Read `.claude/harness.json`'s `models.clarify` key (written by
   `init-harness`) and pass it as the `model` parameter when delegating to
   the `devils-advocate` subagent (`Agent` tool) over the whole change —
   `proposal.md`, `design.md`, the spec deltas, `tasks.md`'s acceptance
   criteria — overriding the agent's own frontmatter default for this run.
   If the manifest or the key is missing, fall back to the agent's own
   default; never block on a missing override.
3. **No findings** — report "no ambiguity found" and stop here. Ask nothing,
   write nothing to the journal. A change with nothing to resolve is a
   silent pass, same as any other clean gate that produced no findings to
   log.
4. **One or more findings** — resolve them one at a time, in the order
   `devils-advocate` reported them. Never batch several findings into one
   question; a list of seven gets seven inattentive answers.

   For each finding:

   a. Show the user the file:line, the quoted text, and both readings
      exactly as `devils-advocate` phrased them.
   b. Ask, via `AskUserQuestion`, a single question offering three options —
      Reading A's wording, Reading B's wording, and **Defer** (the user's own
      free-text "Other" answer is always available too, and counts as its
      own resolution the same way A or B does, as long as it actually states
      a concrete reading — "not sure" or "whatever's easiest" isn't one; ask
      once more what they mean, and treat a second non-answer as Defer
      rather than writing a non-decision into the spec).
   c. **A or B or a custom answer chosen** — edit the file at the cited
      line so it states the chosen reading explicitly, closing the fork, and
      show the user the diff. This is the **clarify** outcome.
   d. **Defer chosen** — ask, in plain conversation rather than another
      `AskUserQuestion` (owner and due date are open text, not a closed
      choice), who owns the question and by when it should be resolved. Do
      not write anything until both are answered — a deferred entry with no
      owner or no date is not a legal outcome, it is the same silent
      closure decision 4 in the design-rationale file argues against. Once
      both are given, append one line under `proposal.md`'s `## Open
      Questions` heading (create the heading at the end of the file if it
      doesn't exist yet):

      ```
      - <file>:<line> — <the finding, one line> — owner: <owner>, due: <date>
      ```

      This is the **defer** outcome.

   Two outcomes, never a third. A finding that's merely acknowledged and
   left as-is is not a legal end state — every finding this step raises gets
   either an edit or an owned, dated entry.

5. Once every finding has an outcome, log each one as a `kind: "finding"`
   line — following `skills/opsx-apply-git/references/log-findings.md`'s
   exact shape, the same one every other gate's CONFIRMED findings already
   use, so no new journal field is introduced:
   - `gate`: `"spec-clarify"`
   - `finding`: the quoted text or a short paraphrase of it
   - `outcome`: `"fixed"` for clarify, `"deferred"` for defer
   - `ruleNumber`: empty — `devils-advocate` carries no numbered rules
6. Report a one-line summary: how many findings, how many clarified, how
   many deferred.

## Handling the result

Once every finding is resolved (or step 3 found none), the change proceeds
to `spec-review` exactly as it would have without this step — this skill
never itself declares a change ready or blocks it; it only makes sure
nothing ambiguous rides silently into that review.

## Notes

- This step never invents which reading is right — that judgment is the
  user's, made in the moment via the question in step 4b. `devils-advocate`
  itself proposes no fix (see its own Write scope) for the same reason:
  separating who finds a fork from who resolves it keeps the finder from
  quietly becoming an advocate for one answer.
- A change can be swept standalone, with no active drafting session to
  attach to — useful for re-checking an already-written change. In that
  case step 4's edits still land as ordinary file edits; there is no
  drafting context to reconcile them against.
