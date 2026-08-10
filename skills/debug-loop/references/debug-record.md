# The debug record — where it goes, and what goes in it

One file per failure being debugged. It is written **as the loop runs**, not
assembled at the end: the run that most needs a record — the one that spends
every attempt and stops — is exactly the run where nothing gets to write a
summary afterwards.

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

**If the file already exists, read it before phase 1.** A slug that collides
means this failure has been debugged before, and the hypotheses that did not
hold last time are the single most useful thing on hand — that reuse is the
reason the record exists at all. Append a new `## Attempt` block under a
fresh date rather than overwriting; never truncate an earlier session's
attempts to make room.

## When each part gets written

| Phase | What gets appended |
|---|---|
| 1. Reproduce | The header, `## Failure`, `## Reproduce`. Written on the first pass only — later attempts reuse them. |
| 1. Reproduce, flake branch | `## Reproduce` records that it did not reproduce twice in a row, what made it flaky, and whether the app degrades gracefully. Then `## Outcome` closes the record. Nothing else follows: a flake spends no attempt, and this record exists precisely because that is the case the harness otherwise forgets entirely. |
| 2. Isolate | The attempt's `Isolated to:` line — including when the cause turns out to be environmental rather than a defect. |
| 3. Diagnose | `Hypothesis:` and `Expected effect:`, **before the fix is applied**. Writing the expectation after seeing the result is how a guess gets recorded as an attempt. |
| 4. Fix and reverify | `What actually happened:` and `Verdict:`. Then either the next `## Attempt` block, or `## Outcome`. |
| After a successful fix | The spec case (1, 2 or 3 from SKILL.md's "three cases"), plus the identifier it touched, into `## Outcome`. |
| Escalation | `## Outcome` records the attempts spent, and the human is given this file's path. |

## The template

```markdown
# <one-line failure title>

- Change: `<change-slug>`, or `—` for a standalone invocation
- Called from: `web-qa` / `code-review` / direct
- First seen: <YYYY-MM-DD>
- Limit in force: `maxFixAttempts: <N>`

## Failure

<what fails, in the words the gate or the user used for it>

## Reproduce

<the minimal reliable trigger from phase 1 — command, URL, input data>

<or, for a flake: did not reproduce twice in a row; what made it flaky;
whether the app degrades gracefully under that condition>

## Attempt <N> — <YYYY-MM-DD>

- Isolated to: <the file or condition from phase 2, or the environment cause>
- Hypothesis: <the root cause named in phase 3>
- Expected effect: <written down before the fix was applied>
- What actually happened: <phase 4's re-run of the phase 1 scenario>
- Verdict: matched / still failing / passed for a different reason

## Outcome

- <Fixed on attempt <N> of <maxFixAttempts>>
  or <Escalated: <N>/<N> attempts spent>
  or <Flake — no fix attempted>
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

This skill writes the record to disk; it does not commit it. Under
`openspec/changes/<change>/` it rides along with that change's next ordinary
commit like any other artifact in that directory. The exhaustion path is the
deliberate exception: `opsx-apply-git`'s own blocked-tasks reference requires
that commit to be the one-line task edit and nothing else, so the record
stays uncommitted on the branch there — on disk, where
the human picking the branch back up will find it at the path the escalation
report named.
