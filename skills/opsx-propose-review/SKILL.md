---
name: opsx-propose-review
description: Proposes a new OpenSpec change, generating all artifacts (proposal, design, specs, tasks) in one step, wrapped with the architecture-review and spec-review gates. Use when starting a new feature or change proposal.
---

Propose a new OpenSpec change and run it through Gates 1-2 before declaring
it ready to implement.

## Steps

1. If `openspec/` doesn't exist yet in this repo, stop and tell the user to
   run `init-harness` first — this skill assumes OpenSpec is already
   initialized.
2. Run the vendored `openspec` proposal flow (`npx openspec` CLI, or the
   vendored `openspec-propose-change` skill if this project has one) to
   generate the full artifact set: proposal, `design.md`, specs, `tasks.md`.
3. Once `design.md` exists, invoke the **`architecture-review`** skill
   (Gate 1) against it.
4. Once every artifact is `status: "done"`, invoke the **`spec-review`**
   skill (Gate 2) against the whole change — this also classifies every
   `tasks.md` group as isolated/judgement-heavy.
5. If either gate raises a CONFIRMED finding, pause and let the user decide
   whether to revise before declaring the change ready.
6. On a clean pass (or PLAUSIBLE-only), report: change name, artifact
   summary, task-group classification table, and that `opsx-apply-git` is
   the next skill to run.
