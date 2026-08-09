# Logging CONFIRMED findings — point 7

Referenced from `SKILL.md` §4 step 6. Background:
`harness-audit/v0.4.0-implemented/03-log-fields.txt` point 7.

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

`spec-clarify` (0.5.0) writes this same line shape too, but on its own
timing rather than at `opsx-apply-git`'s PR-open point — it runs before
implementation starts, once per finding, right after the user resolves it
(`gate: "spec-clarify"`, `outcome: "fixed"` or `"deferred"`, never
`"rejected"` — that outcome value only applies to the four gates above). It
follows the field shape below, not the "when to write this" timing, which
stays specific to `opsx-apply-git`'s own run.

`spec-review` (0.5.0) writes this shape too, but only for its own readiness
checklist (`skills/spec-review/SKILL.md` step 5) — never for `spec-reviewer`'s
own general findings, which stay folded into that gate's single `verdict`
line as before. One line per unmet condition, at the same before-
implementation timing as `spec-clarify` above (`gate: "spec-review"`,
`outcome`: `"fixed"`/`"deferred"`/`"rejected"`, the full three-value set —
unlike `spec-clarify`, an unmet readiness condition can legitimately be
waved off by the user).

## The line

```bash
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg gate "<web-qa|code-review|test-coverage|harness-review>" \
  --arg finding "<short description of what the finding was>" \
  --arg outcome "<fixed|rejected|deferred>" \
  --arg ruleNumber "<CR-nn/SR-nn, or empty>" \
  '{ts:$ts,change:$change,kind:"finding",gate:$gate,finding:$finding,outcome:$outcome,ruleNumber:$ruleNumber}')" \
  >> .claude/harness-log.jsonl
```

If `jq` isn't available, construct the equivalent line with `printf`
instead. A failed log write never blocks the run — note it and move on.

## Fields

- `gate` — which of the four gates (or `spec-clarify` / `spec-review`'s
  readiness checklist, see above) raised the finding.
- `finding` — a short, human-readable description (not a full diff or
  report excerpt).
- `outcome` — exactly one of:
  - `fixed` — `debug-loop` resolved it and the fix landed as a commit; for
    `spec-clarify`, the user picked a reading and the spec was edited on the
    spot instead.
  - `rejected` — a human looked at it and chose not to act (a CONFIRMED
    finding overridden, or a PLAUSIBLE one raised alongside it and judged
    not worth fixing). `spec-clarify` never logs this value — every
    ambiguity it raises is either resolved or deferred, never waved off with
    no trace. `spec-review`'s readiness checklist does use it — a user can
    proceed past an unmet condition on purpose (e.g. a glossary
    contradiction judged acceptable), unlike an ambiguity, which cannot be
    left unresolved.
  - `deferred` — `debug-loop` exhausted `maxFixAttempts` and the run
    stopped to report it instead of resolving it; for `spec-clarify`, the
    user chose to log it under `proposal.md`'s Open Questions with an owner
    and due date instead of resolving it now. `spec-review`'s readiness
    checklist only logs this for its own open-questions condition (an entry
    missing its owner or due date gets one added) — its other four
    conditions have nothing equivalent to defer into.
- `ruleNumber` — optional; the permanent rule code (`agents/code-reviewer.md`
  or `agents/spec-reviewer.md`) the finding was raised under, when the
  raising gate has numbered rules and the finding names one. Empty string
  when it doesn't — `web-qa` and `harness-review` findings have no numbered
  rule to cite yet, and neither does a line written before this field
  existed. A finding without it is still a legal line; nothing downstream
  requires it.

## Why this is a different shape than the other eight lines

This `kind:"finding"` line is deliberately not shaped like the eight
`verdict`-bearing gate-run lines elsewhere in this pipeline. One run can
produce several of these — one per finding — and none of them is a gate run
in its own right, so it carries no `verdict`, `durationMs`, `tokensTotal`,
`model`, `reviewConfidence`, `fixIterations`, or `escalatedToHuman`: those
describe a gate's own execution, not a single finding's fate. `harness-stats`
(`skills/harness-review/references/harness-stats.md`) filters on `kind` to
keep the two record shapes from being summed together.
