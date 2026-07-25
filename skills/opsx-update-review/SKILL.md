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
3. Re-run whichever gates the revision touches:
   - Changed `design.md` → re-run **`architecture-review`** (Gate 1).
   - Changed any artifact, or it's been a while since the last full pass →
     re-run **`spec-review`** (Gate 2), which will also re-classify any
     `tasks.md` groups that changed shape.
4. Do not silently skip re-classification just because the change already
   had marks from a previous pass — a revised group may have shifted from
   isolated to judgement-heavy or vice versa.
5. Report what changed, the gates re-run, and whether the change is still
   ready for `opsx-apply-git` or needs another round.
