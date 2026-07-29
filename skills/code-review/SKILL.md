---
name: code-review
description: Reviews a run's diff for correctness bugs, reuse/simplification/efficiency cleanups, AND test-coverage gaps against this project's standards and threshold, in one delegation (Gate 4 + Gate 5 merged). Use --fix to apply findings. Run once per run — the whole isolated batch's cumulative diff (after every group in it is already committed), or the single judgement-heavy group's diff — before pushing.
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

## Action

1. Determine the diff to review, per `opsx-apply-git`'s two cases: an
   isolated batch's cumulative diff (`git diff <parent>..HEAD`, covering
   every group's commit in the batch) or a judgement-heavy run's single
   group diff (the run *is* one group, so this is already the whole run).
2. Determine whether the Gate 5 section applies: skip it only if that diff
   is docs/config-only (no application source or test files changed) — tell
   the delegated agent this explicitly so it doesn't spend effort walking a
   checklist that doesn't apply.
3. Read `.claude/harness.json`'s `models.code` key (written by
   `init-harness`) and pass it as the `model` parameter when delegating to
   the `code-reviewer` subagent (`Agent` tool) with that diff, the
   Gate-5-applicability note, the detected `testRunner` and
   `coverageThreshold`, and any acceptance criteria as context — overriding
   the agent's own frontmatter default for this run. If the manifest or the
   key is missing, fall back to the agent's own default; never block the
   gate on a missing override.
4. If invoked as `/code-review --fix`, apply the findings the subagent
   suggests once the user confirms which ones.

## Handling the result

The subagent returns two labeled sections, Gate 4 and Gate 5 (or Gate 5
marked not applicable).

- **CONFIRMED finding in either section** — show it to the user and ask
  whether to fix now or continue anyway. A fix lands as its own new commit
  appended to the run's branch — never an amend of an already-committed
  group — and the run's own verification (typecheck/lint/tests) re-runs
  before push, since later groups in the batch may have built on the flawed
  one. Do not push past an unresolved CONFIRMED finding.
- **Clean, or PLAUSIBLE-only in both sections** — proceed to Gate 6's own
  precondition (`opsx-apply-git` §4 step 3).

## Log this gate's run

After delivering the verdict above, append **two** lines to
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
  --argjson durationMs <elapsed-ms> \
  --arg model "<model code-reviewer actually ran on>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model}')" \
  >> .claude/harness-log.jsonl
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<same group-number-or-range>" \
  --arg gate "test-coverage" \
  --arg verdict "<clean|plausible|confirmed|skipped>" \
  --argjson durationMs 0 \
  --arg model "<same model, or empty if the Gate 5 section was skipped>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug and group number or range this run reviewed, each gate's own
verdict (`skipped` for `test-coverage` when its section didn't apply), and
the wall-clock time spent from delegating to `code-reviewer` to receiving
its response — attribute it to whichever line represents the section that
actually did the work; a skipped section logs `0`. If `jq` isn't available,
construct the equivalent JSON lines with `printf` instead. A failed log
write never blocks the gate — note it in the report and move on; this is a
diagnostic aid, not part of the pass/fail logic.
