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
2. **Size assessment (deterministic, before any artifact exists).** Read the
   change as the user just described it and answer three purely observable
   questions — no judgement about how hard it sounds:
   - Does it touch more than one module?
   - Does it change the data schema — a table, column, migration, or any
     persisted shape?
   - Does it change a contract other code depends on — an API endpoint, an
     exported function signature, a shared type, a GraphQL/OpenAPI schema?
     (User-facing copy that nothing else calls is not a contract change — a
     button's label is not "the interface.")

   Any **yes** → **full route**: every step below runs as written. All three
   **no** → **short route**: step 5 (`spec-clarify`) is skipped.

   If `.claude/harness.json`'s `sizeRouting.enabled` is `false`, or the key
   is absent, skip this assessment and treat the change as full route — a
   project that hasn't opted in never gets guessed into the cheaper path.
3. Run the vendored `openspec` proposal flow (`npx openspec` CLI, or the
   vendored `openspec-propose-change` skill if this project has one) to
   generate the full artifact set: proposal, `design.md`, specs, `tasks.md`.
   As soon as the change's folder exists, write step 2's verdict as the
   first line of `openspec/changes/<change>/.route` (`short` or `full`),
   followed by a `# ` comment recording the three answers for audit. A user
   can override a misjudged route later by editing that first line directly
   — this assessment is a starting point, not a verdict.
4. Once `design.md` exists, invoke the **`architecture-review`** skill
   (Gate 1) against it — it reads `.route` itself to decide how deep to go.
5. **Short route only skips this step.** Once every artifact is `status:
   "done"`, invoke the **`spec-clarify`** skill against the whole change —
   it sweeps for ambiguous wording and resolves every finding with the user
   (edit on the spot, or defer to `proposal.md`'s Open Questions with an
   owner and due date) before the change reaches the next step. A change
   with nothing ambiguous passes this silently.
6. Invoke the **`spec-review`** skill (Gate 2) against the whole change —
   this also classifies every `tasks.md` group as isolated/judgement-heavy;
   it too reads `.route` itself for depth.
7. If either gate raises a CONFIRMED finding, pause and let the user decide
   whether to revise before declaring the change ready.
8. On a clean pass (or PLAUSIBLE-only), report: change name, artifact
   summary, the route this change took (`short`/`full`), task-group
   classification table, and that `opsx-apply-git` is the next skill to run.
