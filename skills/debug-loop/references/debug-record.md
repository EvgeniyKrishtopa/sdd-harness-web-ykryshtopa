# The debug record — where it goes, and what goes in it

One file per failure being debugged — per *failure*, not per invocation: the
`code-review` call site hands this loop every CONFIRMED finding of a run at
once, and each of those is its own failure with its own file.

The record is written **as the loop runs**, not assembled at the end: the run
that most needs a record — the one that spends every attempt and stops — is
exactly the run where nothing gets to write a summary afterwards.

## Where the file goes

- **With an OpenSpec change in play** (the `web-qa` and `code-review` call
  sites, and any manual invocation inside a change) →
  `openspec/changes/<change>/_debug/<failure-slug>.md`.
- **Standalone, no change** → `.claude/debug/<failure-slug>.md`. There is no
  `openspec/changes/` directory to write next to in this case, and this skill
  must not create one.

`<failure-slug>` is a short kebab-case name for the failure itself, not for
the attempt or the date — `upload-times-out-over-5mb.md`, not
`debug-2026-08-10.md`. The failure is what a future reader searches for.

Create the directory before the first write, in the same command that writes:

```bash
record="openspec/changes/<change>/_debug/<failure-slug>.md"   # or .claude/debug/<failure-slug>.md
mkdir -p "$(dirname "$record")"
```

## Look for an earlier record first, before phase 1

The same failure resurfacing weeks later, usually under a *different* change,
is the case this record exists for. Per-change paths do not collide on their
own, so look across all of them — including archived changes, which is where
`opsx-apply-git`'s `references/archive-run.md` moves a finished change's
directory:

```bash
ls openspec/changes/*/_debug/ openspec/changes/archive/*/_debug/ .claude/debug/ 2>/dev/null | sort -u
```

Scan that list for a slug describing the same failure, and read any that
matches before spending the first attempt. Hypotheses that didn't hold last
time are the single most useful thing on hand, and re-deriving them is
exactly the waste this record was added to stop.

- **A hit at a different path** → read it, then start a fresh record at this
  change's path, naming the earlier file's path in the header. Never edit a
  finished change's record.
- **A hit at *this* path** (same change, same failure again) → append to it.
  Continue the `## Attempt` numbering, and add a new `## Outcome` at the
  bottom. The file reads top to bottom in time order, so the last `## Outcome`
  is the current one and every earlier attempt survives — never truncate an
  earlier session's attempts to make room.

## When each part gets written

| Phase | What gets appended |
|---|---|
| 1. Reproduce | The header, `## Failure`, `## Reproduce`. Written on the first pass only; a later attempt that re-reproduces the failure *differently* records that in its own block's `Reproduce changed to:` line rather than rewriting `## Reproduce`, so the trigger the failure started with stays readable. |
| 1. Reproduce, flake branch | `## Reproduce` records that it did not reproduce twice in a row, what made it flaky, and whether the app degrades gracefully. This does not close the record: SKILL.md phase 1 sends you back for one more reproduction, and if *that* one succeeds the same file continues into `## Attempt 1` as a normal failure. Only when it stays a flake does `## Outcome` close it — no attempt spent, and this is precisely the case the harness otherwise forgets entirely. |
| 2. Isolate | The attempt's `Isolated to:` line — including when the cause turns out to be environmental rather than a defect, which closes the record with the external-cause outcome and spends no further attempt. |
| 3. Diagnose | `Hypothesis:` and `Expected effect:`, **before the fix is applied**. Writing the expectation after seeing the result is how a guess gets recorded as an attempt. |
| 4. Fix and reverify | `What actually happened:` and `Verdict:`. Then either the next `## Attempt` block, or `## Outcome`. |
| After a successful fix | The spec case (1, 2 or 3 from SKILL.md's "three cases"), plus the identifier it touched, into `## Outcome`. |
| Escalation | `## Outcome` records the attempts spent — written *before* the report, since this branch is where the loop stops — and the human is given this file's path. |

## The template

```markdown
# <one-line failure title>

- Change: `<change-slug>`, or `—` for a standalone invocation
- Called from: `web-qa` / `code-review` / direct
- First seen: <YYYY-MM-DD>
- Limit in force: `maxFixAttempts: <N>`
- Seen before at: `<path to an earlier record>` — only when the lookup hit one

## Failure

<what fails, in the words the gate or the user used for it>

## Reproduce

<the minimal reliable trigger from phase 1 — command, URL, input data>

<or, for a flake: did not reproduce twice in a row; what made it flaky;
whether the app degrades gracefully under that condition>

## Attempt <N> — <YYYY-MM-DD>

- Reproduce changed to: <only when this attempt's fresh reproduction differs
  from the one above — e.g. the 500 became a hang>
- Isolated to: <the file or condition from phase 2, or the environment cause>
- Hypothesis: <the root cause named in phase 3>
- Expected effect: <written down before the fix was applied>
- What actually happened: <phase 4's re-run of the phase 1 scenario>
- Verdict: matched / still failing / passed for a different reason

## Outcome

- <Fixed on attempt <N> of <maxFixAttempts>>
  or <Escalated: <N>/<N> attempts spent>
  or <Flake — no fix attempted>
  or <Not a defect — external cause: <what phase 2 ruled it>>
- Spec case: <1 regression | 2 ambiguous criterion | 3 no criterion covered |
  skipped, because <why>>
- Criterion touched: `<FR-nn / NFR-nn>` — cases 2 and 3 only
```

## What this record is not

It is not a log line, and it does not become one. The invoking gate's own
`harness-log.jsonl` line already carries `fixIterations` and
`escalatedToHuman`, which is everything about this loop that counts. What was
missing was the *content*, and content does not fit in one JSON line — that
is the whole division of labour here. No field is added to the log for it.

## Committing it

A record under `openspec/changes/<change>/_debug/` is committed on its own,
never folded into the fix's commit — the same separation this skill's "three
cases" section already applies to a spec edit, and for the same reason: a
note about how the fix was reached is a different unit of review from the fix.
Append it right after whichever commit the loop's outcome produced (the fix
commit, or the blocked-marker commit on exhaustion, which stays the one-line
task edit `opsx-apply-git`'s blocked-tasks reference requires it to be).
Leaving it uncommitted would repeat exactly the failure that reference names:
a reason for stopping that survives only in an uncommitted diff is as fragile
as one that survives only in chat — and the exhaustion path, where the human
comes back days later to a path named in a report, is where that bites.

A record under `.claude/debug/` is left on disk and not committed. A
standalone invocation has no run, no branch and no change to attach a commit
to; and a committed `.claude/` path would trip `opsx-apply-git`'s Gate 6
precondition on the next run, spending a `harness-review` delegation on a file
that is outside that gate's declared scope.
