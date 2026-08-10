---
name: code-review
description: Reviews a run's diff for correctness bugs, reuse/simplification/efficiency cleanups, AND test-coverage gaps against this project's standards and threshold, in one delegation (Gate 4 + Gate 5 merged), plus a security/architecture deep review on diffs a 0-token risk prefilter flags. Use --fix to apply findings. Run once per run — the whole isolated batch's cumulative diff (after every group in it is already committed), or the single judgement-heavy group's diff — before pushing.
---

Run **Gate 4 and Gate 5** of this project's review pipeline in one
delegation: code review and test-coverage review, merged per
cost-optimization finding #33 — they always reviewed the exact same diff
back to back, so this loads it once instead of twice.

## Trigger

Once per run, not once per group (cost-optimization #34) — `opsx-apply-git`
calls this from its §4 step 2, after every group in the run is already
implemented, verified, and committed (its §3), and — if the run's last
group touched user-facing UI — after Gate 3 (web-qa) has passed or been
ruled not applicable. Skipped entirely by `opsx-apply-git`'s own §4 step 1
trivial-diff pre-filter (cost-optimization #36) before this skill ever runs.

## Requirement-ID coverage (0 tokens, before delegating)

Skip this section entirely, without running it, when step 2 below (Gate 5
applicability) will already rule the diff docs/config-only — there is
nothing to check against and the grep would just discard its own result.

Otherwise run the grep in
`skills/code-review/references/traceability-prefilter.md` and pass its
output to `code-reviewer` as context alongside the diff, so the agent reads
a ready answer instead of deciding coverage from a spec it loaded cold. That
file also explains why its two shell details are load-bearing and why its
three possible outputs — a named list of uncovered identifiers, "all
requirement IDs covered", and "traceability unavailable" — must never be
collapsed into each other.

## Risk prefilter for the deep review (0 tokens, before delegating)

`code-reviewer` has no security rules at all. On a diff that carries real
risk, a second reviewer — `deep-reviewer` — runs on top of it, but only when
a deterministic shell check says the diff is worth the extra delegation.

Run the prefilter in `skills/code-review/references/deep-review.md` and keep
its `$risk` result. Empty → do not spawn `deep-reviewer`, log the skip (see
below), carry on with Gate 4/5 exactly as before. Set (`path` or `content`)
→ run it, per step 5 of Action.

Two things that file settles, and that are easy to get wrong here: the
prefilter is **not** tied to the change's `.route` (the short route skips
documents, never a check on the result), and the deep pass is a **separate
agent** rather than more rules inside `code-reviewer` — because rules added
there would run on every button-label edit too.

## Test plan (0 tokens, before delegating)

Also locate this change's test plan, if it has one, before spawning
`code-reviewer` — a plain file read, no delegation. Read
`openspec/changes/<change>/.route` (missing file → `full`, the same
fallback as above) to know where to look: `full` route →
`openspec/changes/<change>/test-plan.md`; `short` route → the `## Test
Plan` section of `proposal.md`. Pass whatever is found to `code-reviewer`
as further context for Gate 5, alongside the diff. Nothing found (an older
change, or one the `test-plan` skill never ran for) → tell `code-reviewer`
explicitly there is no test plan for this change, so it falls back to its
own requirement-ID-only path instead of silently assuming full coverage.

## Action

1. Determine the diff to review, per `opsx-apply-git`'s two cases: an
   isolated batch's cumulative diff (`git diff <parent>..HEAD`, covering
   every group's commit in the batch) or a judgement-heavy run's single
   group diff (the run *is* one group, so this is already the whole run).
   For a large batch diff (over ~50 KB), `opsx-apply-git` hands this
   delegation a file path and a `<parent>..HEAD` revision range instead of
   the diff text itself (its own §4 step 2) — `Read` that file, or run
   `git diff` over the given range directly; either produces the same diff
   this step would otherwise have received inline. Below that threshold,
   the diff arrives as text, as before.
2. Determine whether the Gate 5 section applies: skip it only if that diff
   is docs/config-only (no application source or test files changed) — tell
   the delegated agent this explicitly so it doesn't spend effort walking a
   checklist that doesn't apply.
3. Determine whether this run is the change's **final run**: read
   `tasks.md` and check whether any `- [ ]` task remains anywhere in it once
   this run's own groups are accounted for — **excluding** any `- [ ]` task
   that carries its own `<!-- blocked: ... -->` marker. A blocked task can
   sit unchecked for many runs by design (`opsx-apply-git` §3 "Blocked
   tasks" skips past a blocked group rather than waiting on it), so counting
   it here would mark every later run "non-final" indefinitely, even ones
   touching code the block has nothing to do with. None remaining (ignoring
   blocked tasks) → final run; anything still open and *not* blocked → not.
   If the only open items left are blocked ones, say so plainly to the user
   alongside the verdict — a review proceeding as "final" specifically
   because a block is being set aside is worth surfacing, not silently
   assumed. Tell the delegated agent the final-run verdict explicitly — it
   only sees the diff and has no way to know this on its own, and it needs
   it to apply the Definition of Done's simplification-downgrade rule
   correctly (`review-gates.md`; `agents/code-reviewer.md`'s Verification
   bar).
4. Read `.claude/harness.json`'s `models.code` key (written by
   `init-harness`) and pass it as the `model` parameter when delegating to
   the `code-reviewer` subagent (`Agent` tool) with that diff — text or
   file-handoff, per step 1 — the Gate-5-applicability note, the final-run
   status, the requirement-ID
   coverage result computed above, the test-plan lookup result, the
   detected `testRunner` and
   `coverageThreshold`, and any acceptance criteria as context — overriding
   the agent's own frontmatter default for this run. If the manifest or the
   key is missing, fall back to the agent's own default; never block the
   gate on a missing override. Also read the manifest's `disabledRules`
   array and pass it along as context — an empty array or missing key means
   nothing is disabled; never invent a value.
5. If the risk prefilter above set `$risk`, delegate to the `deep-reviewer`
   subagent (`Agent` tool) with the same diff — text or file handoff, per
   step 1 — the same `disabledRules` list, and the manifest's `models.deep`
   key as the `model` parameter (missing manifest or key → the agent's own
   frontmatter default; never block on it). Tell it which signal fired,
   `path` or `content`, and on which files: it decides what to read deeply,
   and the signal is the only clue it has about why it was spawned. This is
   a second delegation, deliberately — the two reviewers have different rule
   sets, different verification bars, and (usually) different models. It is
   also the only step in this skill that does not always run.
6. If invoked as `/code-review --fix`, apply the findings the subagent
   suggests once the user confirms which ones.

## Handling the result

The `code-reviewer` subagent returns two labeled sections, Gate 4 and Gate 5
(or Gate 5 marked not applicable). `deep-reviewer`, when it ran, returns one
more. Its findings are handled by exactly the same rules below — a CONFIRMED
`DR-` finding blocks the push the same way a CONFIRMED `CR-` finding does,
and is fixed through the same single `debug-loop` invocation.

- **CONFIRMED finding in any section** — show it to the user and ask
  whether to fix now or continue anyway. "Fix now" runs through the
  `debug-loop` skill (reproduce the finding, isolate, diagnose with a
  recorded expected effect, fix and reverify), bounded by
  `.claude/harness.json`'s `maxFixAttempts`. A fix lands as its own new
  commit appended to the run's branch — never an amend of an
  already-committed group — and the run's own verification
  (typecheck/lint/tests) re-runs before push, since later groups in the
  batch may have built on the flawed one. Do not push past an unresolved
  CONFIRMED finding. If `debug-loop` exhausts `maxFixAttempts` without
  resolving it, follow its escalation for this call site — report-only, no
  blocked-marker (every group in the run is already committed by this
  point, so there's no open task line to mark) — and stop the run instead of
  pushing.
- **Clean, or PLAUSIBLE-only in every section** — proceed to Gate 6's own
  precondition (`opsx-apply-git` §4 step 3).

## Log this gate's run

After delivering the verdict above, append **three** lines to
`.claude/harness-log.jsonl` in the target repo (create the file if it
doesn't exist yet) — one per gate, since downstream cost analysis (#43)
tracks them separately even though this session merged them into a single
delegation. Plain shell appends, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<group-number-or-range>" \
  --arg gate "code-review" \
  --arg verdict "<clean|plausible|confirmed>" \
  --arg skipReason "" \
  --argjson durationMs <elapsed-ms> \
  --argjson tokensTotal <subagent_tokens from the <usage> block> \
  --arg model "<model code-reviewer actually ran on>" \
  --arg reviewConfidence "<high|low, from code-reviewer's own Output>" \
  --argjson fixIterations <total debug-loop attempts across every CONFIRMED finding fixed this run, 0 if none> \
  --argjson escalatedToHuman <true iff debug-loop hit maxFixAttempts on this run> \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<same group-number-or-range>" \
  --arg gate "test-coverage" \
  --arg verdict "<clean|plausible|confirmed|skipped>" \
  --arg skipReason "<только документация, when verdict is skipped; empty otherwise>" \
  --argjson durationMs 0 \
  --argjson tokensTotal 0 \
  --arg model "<same model, or empty if the Gate 5 section was skipped>" \
  --arg reviewConfidence "<same reviewConfidence, or empty if the Gate 5 section was skipped>" \
  --argjson fixIterations 0 \
  --argjson escalatedToHuman false \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<same group-number-or-range>" \
  --arg gate "deep-review" \
  --arg verdict "<clean|plausible|confirmed|skipped>" \
  --arg skipReason "<нет признаков риска, when verdict is skipped; empty otherwise>" \
  --argjson durationMs <elapsed-ms for the deep-reviewer delegation, 0 if skipped> \
  --argjson tokensTotal <subagent_tokens from deep-reviewer's own <usage> block, 0 if skipped> \
  --arg model "<model deep-reviewer ran on, or empty if skipped>" \
  --arg reviewConfidence "<high|low, from deep-reviewer's Output, or empty if skipped>" \
  --argjson fixIterations 0 \
  --argjson escalatedToHuman false \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
```

The `deep-review` line is written on **every** run, including the far more
common one where the risk prefilter found nothing — a gate that logs only
when it fires is indistinguishable from one that silently stopped running.
`нет признаков риска` is its one closed-list skip reason.
`fixIterations`/`escalatedToHuman` are always `0`/`false` on it, for the same
reason the `test-coverage` line carries zeros: a CONFIRMED `DR-` finding is
fixed through the same single `debug-loop` invocation already counted on the
`code-review` line. Unlike the other two lines, this one carries its own
`durationMs` and `tokensTotal` — `deep-reviewer` is a separate delegation
with its own `<usage>` block, not a second section of the first one.

Fill in the change slug and group number or range this run reviewed, each gate's own
verdict (`skipped` for `test-coverage` when its section didn't apply), and
the wall-clock time spent from delegating to `code-reviewer` to receiving
its response — attribute it to whichever line represents the section that
actually did the work; a skipped section logs `0`. `skipReason` follows the
same rule: only the `test-coverage` line ever carries a value, and only
`только документация` — the one closed-list reason that matches "Gate 5
section was docs/config-only" — filled in exactly when that line's own
`verdict` is `skipped`, empty otherwise; the `code-review` line's
`skipReason` is always empty, since that line never logs `skipped` itself.
`tokensTotal` is the `subagent_tokens` figure from the `<usage>` block the
environment appends after the `code-reviewer` delegation returns (see
`harness-audit/v0.4.0-implemented/03-log-fields.txt` point 5) — attributed
entirely to the `code-review` line, the same way `durationMs` is, since one
delegation produces one `<usage>` block covering both sections; the
`test-coverage` line always logs `0` here too. Never estimate either figure
from a proxy; if the `<usage>` block is absent, write `0` and say so in the
report. `reviewConfidence` is the
single `high`/`low` value `code-reviewer` stated for the whole review
(§4 step 2 of `opsx-apply-git` reads this same value for its own
low-without-CONFIRMED surfacing) — the `code-review` line always carries it,
and the `test-coverage` line carries the same value too, except it's empty
when Gate 5 was skipped, mirroring `model` on that same line.
`fixIterations`/`escalatedToHuman` work the same way `reviewConfidence`
does, but land on the `code-review` line only: a CONFIRMED finding from
either section is fixed through the same single `debug-loop` invocation
(`opsx-apply-git` §4 step 2), so recording the attempt count on both lines
would double it in any log-wide sum #U14 computes. The `test-coverage` line
always logs `0`/`false` here, literally — not because Gate 5 never triggers
a fix, but because whatever fix loop ran for it is already counted on the
`code-review` line. If `jq` isn't available,
construct the equivalent JSON lines with `printf` instead. A failed log
write never blocks the gate — note it in the report and move on; this is a
diagnostic aid, not part of the pass/fail logic.
