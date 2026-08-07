# Logging CONFIRMED findings — point 7

Referenced from `SKILL.md` §4 step 6. Background:
`harness-audit/v0.4.0-planned/03-log-fields.txt` point 7.

The eight `verdict`-bearing lines this pipeline already writes to
`.claude/harness-log.jsonl` (one per gate, plus `opsx-apply-git`'s own two
skip forms) record what a gate *said*. None of them record whether that
verdict held up — whether a CONFIRMED finding was actually fixed, or the
human looked at it and moved on, or it never got resolved at all. Without
that, a noisy gate and a trustworthy one look identical in the log.

## When to write this

At the point `SKILL.md` §4 step 6 already forms the run's summary — not
earlier, at the moment each finding is raised. Track each CONFIRMED finding
and its resolution as the run goes (across Gates 3-6: `web-qa`,
`code-review`, `test-coverage`, `harness-review`), then write one line per
finding here, right before opening the PR. A run with no CONFIRMED findings
writes nothing — this section only exists for findings serious enough to
have been CONFIRMED, not for every PLAUSIBLE note.

## The line

```bash
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg gate "<web-qa|code-review|test-coverage|harness-review>" \
  --arg finding "<short description of what the finding was>" \
  --arg outcome "<fixed|rejected|deferred>" \
  '{ts:$ts,change:$change,kind:"finding",gate:$gate,finding:$finding,outcome:$outcome}')" \
  >> .claude/harness-log.jsonl
```

If `jq` isn't available, construct the equivalent line with `printf`
instead. A failed log write never blocks the run — note it and move on.

## Fields

- `gate` — which of the four gates raised the finding.
- `finding` — a short, human-readable description (not a full diff or
  report excerpt).
- `outcome` — exactly one of:
  - `fixed` — `debug-loop` resolved it and the fix landed as a commit.
  - `rejected` — a human looked at it and chose not to act (a CONFIRMED
    finding overridden, or a PLAUSIBLE one raised alongside it and judged
    not worth fixing).
  - `deferred` — `debug-loop` exhausted `maxFixAttempts` and the run
    stopped to report it instead of resolving it.

## Why this is a different shape than the other eight lines

This `kind:"finding"` line is deliberately not shaped like the eight
`verdict`-bearing gate-run lines elsewhere in this pipeline. One run can
produce several of these — one per finding — and none of them is a gate run
in its own right, so it carries no `verdict`, `durationMs`, `tokensTotal`,
`model`, `reviewConfidence`, `fixIterations`, or `escalatedToHuman`: those
describe a gate's own execution, not a single finding's fate. `harness-stats`
(`skills/harness-review/references/harness-stats.md`) filters on `kind` to
keep the two record shapes from being summed together.
