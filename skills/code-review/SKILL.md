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

## Requirement-ID coverage (0 tokens, before delegating)

Before spawning `code-reviewer`, compute Gate 5 criterion 1's answer by
`grep` instead of handing the agent a spec to read cold — the same
cost-optimization logic as the trivial-diff and Gate-6 prefilters in
`opsx-apply-git`:

```bash
change="<change-slug>"
proposal="openspec/changes/$change/proposal.md"
ids_file=$(mktemp)
grep -ohE '\b(FR|NFR)-[0-9]+\b' "$proposal" 2>/dev/null | sort -u > "$ids_file"
if [ ! -s "$ids_file" ]; then
  echo "traceability unavailable: no FR-/NFR- identifiers in $proposal"
else
  uncovered=""
  while IFS= read -r id; do
    grep -rlF "implements $id of $change" \
      --exclude-dir=node_modules --exclude-dir=.git --exclude-dir=openspec \
      . >/dev/null 2>&1 || uncovered="$uncovered $id"
  done < "$ids_file"
  rm -f "$ids_file"
  if [ -z "$uncovered" ]; then
    echo "all requirement IDs covered"
  else
    echo "uncovered requirement IDs:$uncovered"
  fi
fi
```

The `while ... done < "$ids_file"` form (not a pipe into `while`) is deliberate, matching this project's own `.claudeignore` hook: piping into `while read` runs the loop in a subshell in some shells, silently discarding `uncovered` once the loop exits, and a plain `for id in $ids` relies on word-splitting that zsh does not perform on an unquoted expansion by default — either mistake here reports every change as fully covered regardless of what's actually missing.

Pass this output to `code-reviewer` as context alongside the diff, so it
reads a ready answer instead of independently deciding whether the spec is
covered. The three possible outputs are not equivalent and must stay
distinguishable all the way into the agent's report: **a named list of
uncovered identifiers**, **"all requirement IDs covered"**, and
**"traceability unavailable"** (this change's `proposal.md` carries no
identifiers at all). Collapsing the third into the second is the exact
silent failure this check exists to avoid — a change with zero identifiers
would otherwise grep zero, subtract zero, and report full coverage.

## Action

1. Determine the diff to review, per `opsx-apply-git`'s two cases: an
   isolated batch's cumulative diff (`git diff <parent>..HEAD`, covering
   every group's commit in the batch) or a judgement-heavy run's single
   group diff (the run *is* one group, so this is already the whole run).
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
   the `code-reviewer` subagent (`Agent` tool) with that diff, the
   Gate-5-applicability note, the final-run status, the requirement-ID
   coverage result computed above, the detected `testRunner` and
   `coverageThreshold`, and any acceptance criteria as context — overriding
   the agent's own frontmatter default for this run. If the manifest or the
   key is missing, fall back to the agent's own default; never block the
   gate on a missing override.
5. If invoked as `/code-review --fix`, apply the findings the subagent
   suggests once the user confirms which ones.

## Handling the result

The subagent returns two labeled sections, Gate 4 and Gate 5 (or Gate 5
marked not applicable).

- **CONFIRMED finding in either section** — show it to the user and ask
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
  --arg reviewConfidence "<high|low, from code-reviewer's own Output>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model,reviewConfidence:$reviewConfidence}')" \
  >> .claude/harness-log.jsonl
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<same group-number-or-range>" \
  --arg gate "test-coverage" \
  --arg verdict "<clean|plausible|confirmed|skipped>" \
  --argjson durationMs 0 \
  --arg model "<same model, or empty if the Gate 5 section was skipped>" \
  --arg reviewConfidence "<same reviewConfidence, or empty if the Gate 5 section was skipped>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model,reviewConfidence:$reviewConfidence}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug and group number or range this run reviewed, each gate's own
verdict (`skipped` for `test-coverage` when its section didn't apply), and
the wall-clock time spent from delegating to `code-reviewer` to receiving
its response — attribute it to whichever line represents the section that
actually did the work; a skipped section logs `0`. `reviewConfidence` is the
single `high`/`low` value `code-reviewer` stated for the whole review
(§4 step 2 of `opsx-apply-git` reads this same value for its own
low-without-CONFIRMED surfacing) — the `code-review` line always carries it,
and the `test-coverage` line carries the same value too, except it's empty
when Gate 5 was skipped, mirroring `model` on that same line. If `jq` isn't available,
construct the equivalent JSON lines with `printf` instead. A failed log
write never blocks the gate — note it in the report and move on; this is a
diagnostic aid, not part of the pass/fail logic.
