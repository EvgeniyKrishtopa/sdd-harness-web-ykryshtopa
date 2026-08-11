# §5 — auto-archiving once the run's own PR has merged

Read this when the change has no pending tasks left and §4 has already
opened this run's PR. It does not apply on any earlier run.

## Why this waits for the merge

Archiving mutates the parent branch's `openspec/changes/` tree. Doing that
before the run's own PR (opened in §4 step 6) has merged opens a second PR
into the same parent whose content depends on the first — if the run's PR is
later rejected or reworked, an already-opened archive PR would have archived
a change that was never actually accepted (#19).

## The procedure

1. Check the run's PR state. `.claude/harness.json`'s `forge` is `"other"`
   → ask the human directly: has this run's PR merged? Anything else
   (`"github"`, or absent — a manifest written before 0.6.0) → `gh pr view
   <branch-or-number> --json state --jq .state`. Either source resolves to
   the same three outcomes, not two:
   - **`MERGED`** (or the human confirms it) → sync the parent (see the syncing procedure in §3 — the
     same squash/rebase-merge case can apply here too) and cut the archive
     branch off the now-current parent tip, which contains this run's work:
     `git checkout -b chore/archive-<change-name>`.
   - **`OPEN`** (or the human says not yet) → stop here and report — the
     change is fully implemented and its PR is open, but archiving waits on
     that merge. To resume once a human has merged it, re-invoke
     `opsx-apply-git` on **this run's own branch** (not the parent, and not
     a fresh checkout) so it lands back on this same archiving step rather
     than tripping step 1's "leftover group branch" guard in §1, which fires
     when the checked-out branch isn't the current run's own branch.
   - **`CLOSED`** and not merged (or the human says it was rejected or
     reworked) → do **not** wait for a merge that isn't coming — stop and
     ask the human what to do with the change instead (re-open, rework, or
     abandon the archive entirely).
2. Run `openspec archive <change-name>` (or the vendored
   `openspec-archive-change` skill if present).
3. Commit the archive move (`chore: archive <change-name>`) — this is a
   second, narrower override of "never commit without being asked," same
   justification as §3's per-group commit override.
4. Push the archive branch, open a PR into the parent. Leave it open.
5. Regenerate `PROGRESS.md` one final time for this change (clock-out): no
   current change and no next steps remain for it, noting the archive
   location and archive PR URL — the same self-checking regeneration as §4
   step 7, just for a change that's now fully done rather than paused,
   including the same `## Paused changes` prune-this-change-only-if-present
   rule from §4 step 7. Then report the full session: every group completed
   with PR URLs, final `N/N tasks complete`, archive location, archive PR
   URL.
