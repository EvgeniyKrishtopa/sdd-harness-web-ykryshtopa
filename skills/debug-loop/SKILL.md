---
name: debug-loop
description: Bounded, four-phase fix loop for a reproducible failure — reproduce, isolate (environment-first), diagnose with a recorded expected effect, fix and reverify the same scenario — up to maxFixAttempts before escalating to a human. Not a review gate — it blocks nothing on its own, isn't listed in review-gates.md, and doesn't get a seventh-gate number. Runs inline in the calling session, no subagent. Invoked from a web-qa FAIL, a code-review CONFIRMED finding the user chose to fix, or directly by the user for a failure outside any gate.
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
   - Matches the expectation → the loop ends here; report success and the
     number of attempts it took.
   - Still fails, or passes for a different reason than expected → this
     attempt is spent. Below `maxFixAttempts` → back to phase 1 with a fresh
     reproduction, since the failure may have changed shape. At
     `maxFixAttempts` → stop. Do not make a
     (`maxFixAttempts` + 1)th attempt — go to Escalate.

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
does; the attempt count and escalation flag this loop produces join that log
line in a later release (#U13), once there's a bounded, numbered loop for
those fields to describe.
