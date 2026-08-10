---
name: debug-loop
description: Bounded, four-phase fix loop for a reproducible failure — reproduce, isolate (environment-first), diagnose with a recorded expected effect, fix and reverify the same scenario, then classify the fix against the spec — up to maxFixAttempts before escalating to a human. Not a review gate — it blocks nothing on its own, isn't listed in review-gates.md, and doesn't get a seventh-gate number. Runs inline in the calling session, no subagent. Invoked from a web-qa FAIL, a code-review CONFIRMED finding the user chose to fix, or directly by the user for a failure outside any gate.
---

Run a fix attempt as four explicit phases instead of "try something and see."
This skill exists because a fix loop without a limit or a structure is the
one place in this harness where cost can run unbounded — see the CLAUDE.md
pointer block for why that's a global concern here, not just a workflow
preference.

## Not a gate

This skill never appears in `review-gates.md` and never blocks a push on its
own. It's a workflow the gates above it (and the user, directly) call into
when there's a concrete failure to fix. If nothing is broken, there's nothing
for this skill to do.

## Read the limit

Read `.claude/harness.json`'s `maxFixAttempts` (seeded by `init-harness`,
default `2`). If the manifest or the key is missing, fail closed to `2` —
the same treatment `trivialDiffThreshold` gets — rather than guessing higher
or looping unbounded. This is the total number of fix attempts allowed for
one failure before escalating, not additional retries layered on top of a
free first try.

## The four phases, once per attempt

1. **Reproduce** — the minimal, reliable way to trigger the failure. If it
   doesn't reproduce twice in a row, it's a flake, not a fix target: note it
   as a separate line of investigation (what made it flaky, whether the app
   degrades gracefully under that condition) and don't spend an attempt on
   it — go back to reproducing once more before deciding whether a real fix
   is even in scope.
2. **Isolate** — narrow the failure to the specific file or condition
   responsible. For a `web-qa`-triggered failure, rule out an environment
   condition *first* — a third-party API rate limit, flaky animation timing
   — note it and re-run rather than treating it as a defect, though the app
   must still degrade gracefully under that condition. (This check used to
   live in `web-qa`'s own fix-loop step 1; it lives here now, and `web-qa`
   delegates its whole fix loop to this skill.)
3. **Diagnose** — name the root cause, and record the *expected effect* of
   the fix *before* applying it: one or two sentences on what should be
   different once it lands. This recorded expectation, written down ahead of
   the fix, is what phase 4 checks against — it's the one thing that tells a
   real attempt apart from a guess.
4. **Fix and reverify** — apply the fix, then re-run *exactly* the scenario
   from phase 1 (not a broader pass) and compare the outcome against phase
   3's expectation.
   - Matches the expectation → classify the fix against the spec (see
     "After a successful fix: three cases" below), then report success and
     the number of attempts it took.
   - Still fails, or passes for a different reason than expected → this
     attempt is spent. Below `maxFixAttempts` → back to phase 1 with a fresh
     reproduction, since the failure may have changed shape. At
     `maxFixAttempts` → stop. Do not make a
     (`maxFixAttempts` + 1)th attempt — go to Escalate.

## After a successful fix: three cases

A fix that stops the moment its test goes green leaves the spec exactly as
it was when it let the defect through — the next task to touch this area
inherits the same gap. Classify every defect this loop actually fixed
(phase 4 matched its expectation) into exactly one of three cases before
reporting success, unless one of these applies — then skip straight to
reporting success as before:

- Phase 2 already ruled the cause external (a third-party rate limit, an
  environment/flake condition) rather than a defect in this codebase's own
  logic — there is nothing to feed back into a spec that never claimed to
  cover it.
- This invocation has no OpenSpec change behind it — a standalone fix with
  no `openspec/changes/<change>/` in play. Say so plainly and stop; there is
  no spec to check it against.

Otherwise, read phase 3's diagnosis against the change's `proposal.md` (and
its spec deltas) for the FR-/NFR- identifier whose Given/When/Then criteria
cover the affected behavior:

1. **Criterion exists and was violated** — the Then line already states the
   behavior the fix restores; this is a regression, not a spec gap. Confirm
   a test pins this exact scenario (write one now if phase 4's
   reverification was a manual repro only). The spec is not touched.
2. **Criterion exists but is ambiguous** — the Then line's wording was loose
   enough that the pre-fix behavior was also a legal reading of it; this
   defect fell through the same kind of fork `spec-clarify` looks for,
   just found after the fact. Edit the Then line in place so it states the
   reading the fix actually implements, and show the user the diff — the
   same clarify action `spec-clarify` step 4c takes, done directly here
   since there is no fresh ambiguity to hunt for, only one to record.
3. **No criterion covers this behavior at all** — the most common and least
   comfortable case: the change shipped with a gap in its requirements. Add
   a new Given/When/Then criterion under the relevant FR-/NFR- (or a new
   identifier if none fits), stating the behavior the fix now guarantees,
   tagged `(added by defect fix)` right after the identifier so the entry
   stays visibly written after the fact rather than during drafting.

Cases 2 and 3 both edit `proposal.md` or a spec delta the way
`opsx-update-review` step 2 does — apply the revision directly to that
artifact — then show the user the diff yourself; do not go on to run
`opsx-update-review` steps 3-4, which re-run
`architecture-review`/`spec-clarify`/`spec-review` through fresh subagent
dispatches. This classification and its edit happen entirely in the current
session, off the diagnosis already on hand — no new agent run, matching
every other call site in this skill's own `## Call sites` section below,
none of which spawns a subagent either. The edited artifact gets its next
real gate pass on this change's own ordinary cycle, not as a side effect of
the fix. Commit the edit on its own, never folded into the code fix's
commit — a spec change and a code change are different units of review even
when one caused the other. Append it right after whichever commit carries
the fix lands (for the `web-qa` call site, that means after the group's own
commit, once the fix has actually folded into it and Gate 3 clears).

Report which of the three cases applies (or that it was skipped, and why)
in one line, alongside the success report.

## Escalate once the limit is reached

- Do not attempt a fix beyond `maxFixAttempts`.
- **`web-qa` call site** — the failing group's task line is still uncommitted
  at this point (`opsx-apply-git` runs Gate 3 *before* that group's own
  commit): write `<!-- blocked: <reason> -->` on that specific task line,
  first reverting its checkbox back to `- [ ]` if phase 1 of an earlier
  attempt had already flipped it to `- [x]`, and commit that one-line edit on
  its own — exactly the mechanism `opsx-apply-git`'s own §3 "Blocked tasks"
  section already defines ("the task itself stays uncommitted and unchecked;
  only the marker is committed"). Reuse it directly rather than inventing a
  second way to mark a stop; this skill runs in the same session that
  already has that context loaded. Keep `<reason>` compact enough to survive
  as `PROGRESS.md`'s single physical `Blocked:` line (e.g. `debug-loop: 2/2
  attempts exhausted, see commit body`) and put the full per-attempt
  hypothesis-and-result detail in that commit's own body, the same "what,
  why, how it was validated" shape `git-conventions.md` already requires of
  every commit. `opsx-apply-git`'s next run-boundary regeneration (§4 step 7)
  then carries that reason into `PROGRESS.md` as it already does for any
  other blocked task — nothing new to write there.
- **`code-review` call site** — this one never gets a blocked-marker. By the
  time `code-review` runs (`opsx-apply-git` §4, after every group in the run
  is already committed), there is no open task line left to mark — every
  box in this run is already `- [x]` and its commit already made, and a
  CONFIRMED finding on the run's cumulative diff doesn't necessarily trace to
  one task anyway. Report-only: stop the run, leave the branch exactly as it
  is (no push), and hand the human the full attempt history — the same
  outcome `opsx-apply-git` §4 step 2 already describes for this case.
- **Standalone, manual invocation** (no `opsx-apply-git` run in progress at
  all): same as the `code-review` call site — there's no `tasks.md` line to
  mark and no run boundary that will regenerate `PROGRESS.md`. Say so
  plainly, and report the full attempt history directly to the user.
- In every case, hand the human every hypothesis from every attempt, not
  just the last one — that's the entire point of recording the expectation
  in phase 3: the escalation reads as "here's what we tried and why it
  didn't hold," not "it didn't work twice."

## What this loop does not do

It never rolls back automatically via `git reset` or a rebase. An
unsuccessful attempt's edits either stay uncommitted, or — if an attempt was
already committed — get undone with a new `git revert` commit. This mirrors
`opsx-apply-git`'s own `§ Exceptions`: destructive/history-rewriting
operations are never part of this flow, and this skill doesn't carve out a
second exception to that rule. Leaving the branch exactly where it stopped
and handing the decision to a human is always an acceptable outcome; a
silently rewritten history is not.

## Call sites

- **`web-qa` (Gate 3) FAIL** — the entire fix loop in web-qa's "must-pass
  gate with a fix loop" section is this skill, scoped to the failing
  flow(s). A fix folds into the current group's own diff, same as before.
  Uses the blocked-marker branch of Escalate above on exhaustion.
- **`code-review` (Gate 4/5) CONFIRMED**, once the user has chosen "fix
  now" — the fix runs through this loop instead of a single ad hoc edit,
  still landing as its own new commit appended to the run's branch. Uses the
  report-only branch of Escalate above on exhaustion — every group in the
  run is already committed by the time this call site runs, so there is no
  open task line left to mark.
- **Direct, manual invocation** by the user for a failure outside any gate.
  Uses the report-only branch of Escalate above on exhaustion.

No subagent is spawned for any of these — this skill reads the diff, the
gate's own output, and the attempt history straight out of the calling
session's own context, the same reasoning that merged Gate 4 and Gate 5 into
one delegation rather than two.

## Log

This skill doesn't write its own `harness-log.jsonl` line — it isn't a gate.
The gate that invoked it (`web-qa` or `code-review`) logs as it already
does, folding the attempt count and escalation flag this loop produces into
that log line's `fixIterations`/`escalatedToHuman` fields (#U13) — see
those gates' own `## Log this gate's run` sections for exactly what each
field means at their call site.
