---
name: opsx-apply-git
description: Implements the next run from an OpenSpec change — an autonomous batch of consecutive isolated task groups, or a single judgement-heavy group with a human in the loop — inside a branch-per-group git workflow with the project's review gates, auto-committing each group when green, opening one PR per run into the parent branch, and auto-archiving via its own PR once that run's PR has merged. Use instead of the vendored openspec-apply-change whenever the user wants to implement, continue, or work through OpenSpec tasks.
---

Implement the next run from an OpenSpec change inside this project's git
workflow and review gates — not just checking task boxes.

**One run per invocation.** A "run" is either an autonomous batch of
consecutive `isolated` groups or a single `judgement-heavy` group. Work the
run to completion, then stop and report — do not start the next run in the
same session. If the run finished the last pending group, continue straight
into archiving (step 5) instead of stopping at the report — but step 5
itself may need to stop and wait there for a human to merge the run's PR
first (see below).

## 0. Read the harness docs first

Read `.claude/docs/git-conventions.md` and `.claude/docs/review-gates.md` in
the target repo (written by `init-harness`) before touching any code — they
are the source of truth for branch naming, commit format, and gate order.

## 1. Determine the parent branch and read the stack manifest

1. `git branch --show-current` — this should be the parent feature branch
   already active, never `main`/`master`. If it looks like a leftover group
   branch, stop and ask which branch is the real parent.
2. Read `.claude/harness.json` (written by `init-harness`) for
   `packageManager`, `runCmd`, `framework`, `testRunner`, `buildDir`,
   `scripts`, `devServerUrl`, and `coverageThreshold` — every verification
   command below depends on these, not on assuming `yarn`/Vite. Do not
   re-detect the stack from lockfiles or config files. If the manifest is
   missing, stop and tell the user to run `init-harness` first — see
   `${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/stack-detection.md`
   for what it detects and why this skill doesn't duplicate that logic.

## 2. Standard OpenSpec selection and context

1. Select the change (explicit name, inferred, or ask via `AskUserQuestion`).
2. `openspec status --change "<name>" --json` for schema and progress.
3. `openspec instructions apply --change "<name>" --json` for context files
   and the task list.
4. Read every file under `contextFiles`.

## 3. Work the next run: isolated batch, or one judgement-heavy group

A "group" is a numbered `##` heading in `tasks.md`, not a sub-task. Read the
`<!-- isolated -->` / `<!-- judgement-heavy -->` marks `spec-review` wrote.
**An unmarked group counts as judgement-heavy** — never auto-run an
unclassified group.

### Syncing the parent (used by both cases below)

`git fetch origin && git pull --ff-only` (skip entirely if the parent has no
upstream yet) is the happy path. It fails as soon as a previous run's PR was
merged with squash or rebase — common defaults on many repos — because the
parent's local history no longer has a commit that's an ancestor of
`origin/<parent>`, so a fast-forward is impossible even though nothing was
actually lost. Don't treat that failure as a hard stop without checking which
case it is:

1. Run `git fetch origin`, then `git pull --ff-only`.
2. On failure, check **both** directions before concluding anything:
   `git log --oneline <parent>..origin/<parent>` (what's new upstream) *and*
   `git log --oneline origin/<parent>..<parent>` (what's local-only, not on
   `origin` at all). The squash/rebase-merge case is specifically: the first
   command shows a single squashed commit (or rebased sequence) that
   supersedes exactly what this branch already had, **and** the second
   command is empty — no local-only commits exist for `reset --hard` to
   discard. If the second command shows anything, this isn't the safe case:
   there's un-pushed local work that `reset --hard` would destroy, even if
   the first command also looks like a clean squash.
3. Only when the local-only side is empty, propose `git reset --hard
   origin/<parent>` to the user and get **explicit confirmation** before
   running it. This is the one documented, narrowly-scoped exception to this
   skill's rule against destructive/history-rewriting operations (see
   Exceptions below) — it's safe here only because the squashed/rebased
   commit already contains everything the local branch had and nothing
   local-only would be lost, and it must never run without that
   confirmation (#18).
4. If the divergence doesn't match that exact shape — local-only commits
   exist, the upstream side doesn't look like a clean squash/rebase, or
   anything else is ambiguous — stop and ask. Don't guess at a merge, rebase,
   or reset yourself.

### Case A — first pending group is isolated: autonomous batch

1. Sync the parent (see above), cut one batch branch off it
   (`<type>/<change>-isolated`, per git-conventions.md naming).
2. For each isolated group in turn: implement its sub-tasks (minimal,
   focused; mark `- [ ]` → `- [x]`). If a design decision surfaces mid-group,
   the classification was wrong — stop, leave it uncommitted, tell the user.
3. Once green (its own verification + lint), run the per-group gates (§4),
   commit the group on the batch branch.
4. Next pending group: isolated → continue the loop; judgement-heavy or none
   left → end the batch, go to §4.8.
5. Any mid-batch pause (CONFIRMED finding, error, ambiguity) stops the batch
   where it is — report and wait, never commit a half-finished group.

### Case B — first pending group is judgement-heavy: one group, human in the loop

1. Sync the parent (see above), cut a single group branch off it, named for
   the group.
2. Announce why it's judgement-heavy. Implement with the standard
   guardrails, but pause and ask on every design decision or ambiguity.
3. Once green, run §4 for this one group, then go to §4.8.

## 4. Review + commit each group, push + PR once per run

Steps 4.1-4.7 run per group; 4.8-4.11 run once per run.

1. Review the group's diff (`git status -s`, `git diff --stat`) — confirm
   scope, no unrelated files.
2. Determine if this is the last group (any `- [ ]` left elsewhere in
   `tasks.md`?). Remember the answer for steps 3, 6, and 4.11.
3. **Last group + touched user-facing UI** → run **`web-qa`** (Gate 3)
   before code-review, using the detected framework's dev-server command.
   Must-pass with a fix loop (see that skill). Skip to 4.4 otherwise.
4. Run **`code-review`** (Gate 4) against the group's diff (incl. any web-qa
   fixes). CONFIRMED → pause and ask fix-now-or-commit-anyway. Clean/
   PLAUSIBLE → continue.
5. Unless the group's diff is docs/config-only, run **`test-coverage`**
   (Gate 5) against the same diff, using the detected test runner and the
   coverage threshold `init-harness` recorded — this runs precisely when a
   group touched source code, whether or not it also touched tests, since a
   group that shipped source changes with no tests is what this gate exists
   to catch. Same pause behavior.
6. **Last group** → run **`harness-review`** (Gate 6) before committing. On
   an approved finding, apply the fix and commit it separately — never
   `git commit -a`/`-am`, which would sweep in the group's own
   not-yet-committed implementation still sitting in the working tree. Stage
   **exactly the files the fix touched** with explicit paths
   (`git add <the-touched-file(s)>`), never a directory shorthand like
   `.claude/` that could also pick up unrelated uncommitted changes the
   group's own implementation left under the same directory. Gate 6's scope
   bounds where those files can come from — `CLAUDE.md`/`AGENTS.md`,
   `.claude/harness.json`, `.claude/settings.json`, `.claude/docs/**`,
   `.husky/**`, plus this plugin's own `skills/`/`agents/` when its own repo
   is what's under review — but the `git add` itself always lists the
   specific file(s), e.g.
   `git add .husky/pre-commit && git commit -m "chore: harness review — <summary>"`.
   Do this before step 7.
7. Commit the group's own implementation (Conventional Commits, per
   git-conventions.md) — do not wait to be asked, this is the documented
   override for group boundaries. If the pre-commit hook fails, fix the
   root cause and recommit, never `--no-verify`. In a batch, loop back to
   §3 Case A step 2 for the next group; 4.8-4.11 only run once the batch ends.
8. Push the run's branch (`git push -u origin <branch>`).
9. Ensure the parent branch exists on `origin` (push it first if local-only).
10. Open one PR from the run's branch into the parent (`gh pr create`),
    covering every group in this run. **Judgement-heavy run** → lead the PR
    body with `⚠️ Judgement-heavy: needs careful human review`. Leave it
    open — the human owns the merge.
11. **Tasks remain** → report progress and stop; the next `opsx-apply-git`
    invocation re-syncs the parent from `origin` (only picks up this run's
    work once its PR is merged). **No tasks remain** → continue to step 5.

## 5. Auto-archive once the run's own PR has merged

Archiving mutates the parent branch's `openspec/changes/` tree. Doing that
before the run's own PR (opened in step 4.10) has merged opens a second PR
into the same parent whose content depends on the first — if the run's PR
is later rejected or reworked, an already-opened archive PR would have
archived a change that was never actually accepted (#19).

1. Check the run's PR state: `gh pr view <branch-or-number> --json state
   --jq .state`. Three outcomes, not two:
   - **`MERGED`** → sync the parent (see the syncing procedure in §3 — the
     same squash/rebase-merge case can apply here too) and cut the archive
     branch off the now-current parent tip, which contains this run's work:
     `git checkout -b chore/archive-<change-name>`.
   - **`OPEN`** → stop here and report — the change is fully implemented and
     its PR is open, but archiving waits on that merge. To resume once a
     human has merged it, re-invoke `opsx-apply-git` on **this run's own
     branch** (not the parent, and not a fresh checkout) so it lands back on
     this same archiving step rather than tripping step 1's "leftover group
     branch" guard in §1, which fires when the checked-out branch isn't the
     current run's own branch.
   - **`CLOSED`** (and not merged) → the run's PR was rejected or reworked.
     Do **not** wait for a merge that isn't coming — stop and ask the human
     what to do with the change instead (re-open, rework, or abandon the
     archive entirely).
2. Run `openspec archive <change-name>` (or the vendored
   `openspec-archive-change` skill if present).
3. Commit the archive move (`chore: archive <change-name>`) — this is a
   second, narrower override of "never commit without being asked," same
   justification as step 4.7.
4. Push the archive branch, open a PR into the parent. Leave it open.
5. Report the full session: every group completed with PR URLs, final
   `N/N tasks complete`, archive location, archive PR URL.

## Exceptions

- An unrelated fix found mid-task can land as its own focused commit.
- Destructive/history-rewriting git operations are never part of this flow
  — stop and ask if something goes wrong. The **only** exception is the
  confirmed `git reset --hard origin/<parent>` in the squash/rebase-merge
  recovery above (§3), and only under the exact narrow conditions and
  explicit human confirmation described there — it is not a general license
  to reset, and nothing else in this flow rewrites history or discards
  commits.
