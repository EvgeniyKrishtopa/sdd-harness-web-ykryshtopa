---
name: opsx-propose-review
description: Proposes a new OpenSpec change, generating all artifacts (proposal, design, specs, tasks) in one step, wrapped with the architecture-review and spec-review gates. Use when starting a new feature or change proposal.
---

Propose a new OpenSpec change and run it through Gates 1-2 before declaring
it ready to implement.

## Steps

0. **Project-level WIP check (deterministic, 0 tokens), before proposing
   anything.** `opsx-apply-git` already enforces WIP=1 *within* a single run
   ("one run per invocation... do not start the next run in the same
   session"); nothing enforced it across separate `opsx-propose-review`
   invocations. Both failure modes this guards against — overreach (several
   changes started, none finished) and under-finish (code scattered
   everywhere, green nowhere) — happen at exactly this gap.

   First check whether `openspec/` exists at all (`test -d openspec/`, 0
   tokens, no command invoked) — if it doesn't, there's nothing to check
   yet; skip straight to step 1, which stops and tells the user to run
   `init-harness` first. Only once it exists, run `npx openspec list` (or,
   if unavailable, list `openspec/changes/*/` directories and exclude
   `archive/`) to check for a change already proposed but not yet archived:
   - **None found** → continue silently to step 1. Asking on every clean
     proposal would just be noise.
   - **The command itself errors** (not "no changes" — a real failure:
     network, a corrupted `openspec/` state, anything else) → surface the
     error to the user and stop; don't guess which case it was.
   - **One or more found** → name the change(s) and ask via
     `AskUserQuestion`, offering three options — none of them a hard block:
     1. **Continue the existing change** — stop this flow here and point the
        user at `opsx-apply-git` for it instead.
     2. **Pause it explicitly, with a reason** — add a line for it under
        `PROGRESS.md`'s `## Paused changes` section
        (`${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/progress-template.md`,
        create the section if it
        doesn't exist yet), so it's visible to anyone reading the file. This
        is a *different* change than whatever `PROGRESS.md`'s own
        `Current change`/`Status` sections describe — never write it into
        the `Blocked:` line there, which is `opsx-apply-git`'s and scoped to
        a task-level `<!-- blocked: ... -->` marker (#U4) inside the
        *active* change, not a whole other change being set aside.
        `opsx-apply-git` removes this change's own line from
        `## Paused changes` the next time it resumes work on it (§4 step
        7 / §5 step 5) — this skill only ever appends. Then continue to
        step 1 for the new change.
     3. **Start the new one anyway, in parallel** — continue to step 1
        without pausing the existing change. A deliberate choice the user is
        allowed to make; the point of this check is to make it a choice, not
        to forbid it.
1. If `openspec/` doesn't exist yet in this repo, stop and tell the user to
   run `init-harness` first — this skill assumes OpenSpec is already
   initialized.
2. Run the vendored `openspec` proposal flow (`npx openspec` CLI, or the
   vendored `openspec-propose-change` skill if this project has one) to
   generate the full artifact set: proposal, `design.md`, specs, `tasks.md`.
3. Once `design.md` exists, invoke the **`architecture-review`** skill
   (Gate 1) against it.
4. Once every artifact is `status: "done"`, invoke the **`spec-clarify`**
   skill against the whole change — it sweeps for ambiguous wording and
   resolves every finding with the user (edit on the spot, or defer to
   `proposal.md`'s Open Questions with an owner and due date) before the
   change reaches the next step. A change with nothing ambiguous passes this
   silently.
5. Invoke the **`spec-review`** skill (Gate 2) against the whole change —
   this also classifies every `tasks.md` group as isolated/judgement-heavy.
6. If either gate raises a CONFIRMED finding, pause and let the user decide
   whether to revise before declaring the change ready.
7. On a clean pass (or PLAUSIBLE-only), report: change name, artifact
   summary, task-group classification table, and that `opsx-apply-git` is
   the next skill to run.
