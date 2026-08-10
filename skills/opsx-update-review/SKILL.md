---
name: opsx-update-review
description: Revises an existing OpenSpec change's planning artifacts and re-runs the relevant review gates to keep them coherent. Use when reworking a change's plan after review feedback or a scope shift.
---

Revise an existing OpenSpec change and re-validate it.

## Steps

1. Identify the change (explicit name, or infer from conversation — confirm
   with the user which change if ambiguous, via `AskUserQuestion`).
2. Apply the requested revision to the relevant artifact(s)
   (`proposal.md`/`design.md`/specs/`tasks.md`).
3. Re-run whichever gates the revision touches, in this order — same as
   `opsx-propose-review`'s own sequence:
   - Changed `design.md` → re-run **`architecture-review`** (Gate 1) first.
   - Changed any artifact → then re-run **`spec-clarify`** — the revision
     itself may have introduced a new fork, and a change that already
     resolved ambiguities once is not exempt from raising new ones on a
     later edit — and only then **`spec-review`** (Gate 2), which will also
     re-classify any `tasks.md` groups that changed shape.
4. Do not silently skip re-classification just because the change already
   had marks from a previous pass — a revised group may have shifted from
   isolated to judgement-heavy or vice versa.
5. If the revision added, removed, or reworded any acceptance criterion,
   re-run **`test-plan`** for a fresh table. A plan built against the
   previous wording is worse than none: `code-review`'s Gate 5 trusts it as
   the coverage floor, so a stale row quietly certifies a criterion nobody
   tests. Leave the plan alone when the revision touched neither the
   criteria nor the requirement identifiers.
6. Report what changed, the gates re-run, whether the test plan was
   rebuilt, and whether the change is still ready for `opsx-apply-git` or
   needs another round.

## Called from `debug-loop`

`debug-loop`'s post-fix spec classification (see `skills/debug-loop/
SKILL.md`, "After a successful fix: three cases") applies step 2 above to
the relevant criterion — locate the artifact, edit it in place — and shows
the user the diff itself, but stops there. It never continues into steps
3-4: those re-run gates through fresh subagent dispatches, and a defect
classification already inline in the calling session must not grow the
number of agent runs a fix takes. The edited artifact still gets a real
gate pass — on this change's own next ordinary cycle, not as a side effect
of the fix.
