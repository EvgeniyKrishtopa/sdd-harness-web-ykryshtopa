# Logging CONFIRMED findings — point 7

Referenced from `SKILL.md` §4 step 6. Background:
`harness-audit/v0.4.0-implemented/03-log-fields.txt` point 7.

The nine `verdict`-bearing lines this pipeline already writes to
`.claude/harness-log.jsonl` (one per gate, plus `opsx-apply-git`'s own two
skip forms) record what a gate *said*. None of them record whether that
verdict held up — whether a CONFIRMED finding was actually fixed, or the
human looked at it and moved on, or it never got resolved at all. Without
that, a noisy gate and a trustworthy one look identical in the log.

## When to write this

At the point `SKILL.md` §4 step 6 already forms the run's summary — not
earlier, at the moment each finding is raised. Track each CONFIRMED finding
and its resolution as the run goes (across Gates 3-6: `web-qa`,
`code-review`, `test-coverage`, `deep-review`, `harness-review`), then write one line per
finding here, right before opening the PR. A run with no CONFIRMED findings
writes nothing — this section only exists for findings serious enough to
have been CONFIRMED, not for every PLAUSIBLE note.

This same tracked list also feeds the PR's "Review trail" section below —
collected once, as the run goes, and read back for both destinations. Never
re-derive it a second time by re-reading `.claude/harness-log.jsonl`: that
file can hold `kind:"finding"` lines from earlier runs of the same `change`
too, with no field distinguishing which run wrote which, so the in-session
list is the only reliable source for "this run's findings."

## Composing the PR's "Review trail" section (point 3)

Immediately after "What changed and why" in the same PR body. Four parts,
each short — this is the whole point: a reviewer reads it in under a
minute, not a dump of the log.

1. **Change** — one line linking to `openspec/changes/<name>/`, so a
   reviewer reaches the proposal, acceptance criteria, and test plan
   themselves.
2. **Checks** — one line per each of the six review checks, six lines
   maximum: `architecture-review`, `spec-review`, `web-qa`, `code-review`,
   `test-coverage`, `harness-review`. For Gates 3-6, use this run's own
   verdict/`skipReason` already determined earlier in this run (`web-qa` in
   §3; `code-review`/`test-coverage` in §4 step 2; `harness-review` in §4
   step 3) — don't re-read the log for those. `architecture-review`/`spec-review` ran once
   at change scope, possibly in an earlier session, so read each one's
   latest matching line instead:
   ```bash
   jq -c --arg change "<change-slug>" --arg gate "<gate-name>" \
     'select(.change == $change and .gate == $gate and has("verdict"))' \
     .claude/harness-log.jsonl | tail -n 1
   ```
   A `skipped` verdict always carries one of the closed-list reasons already
   written elsewhere in this pipeline — `интерфейс не затронут`, `только
   документация`, `мелкое изменение`, or `настройки плагина не менялись` —
   print it verbatim next to the verdict. No matching line for a gate → say
   so on that gate's line rather than omitting it.
3. **Findings** — this run's CONFIRMED findings from the tracked list above:
   rule number, one-line description, outcome. PLAUSIBLE notes never appear
   here. More than ten → print the first ten and one closing line, "...and
   `<N>` more, see `.claude/harness-log.jsonl`." No CONFIRMED findings →
   one explicit line saying so; never omit this part.
4. **Deferred** — one line per entry currently under `proposal.md`'s
   `## Open Questions` heading, verbatim (owner and due date are already
   part of that line's format — see `spec-clarify`). No such heading, or
   it's empty → one explicit line saying so.

This section is assembled entirely from data this pipeline already writes
elsewhere — this run's own gate verdicts, the findings list above, and
`proposal.md`'s Open Questions. It never introduces a new
`.claude/harness-log.jsonl` field to answer a question the log doesn't
already record.

## Committing the log (point 4)

`.claude/harness-log.jsonl` was a local, never-committed file before 0.6.0
— every gate above appended to it, but nothing staged it, so it never
outlived the machine that wrote it. `SKILL.md` §4 step 6.2 closes that gap:
right there, after this run's Review trail section is composed and before
step 6.3 opens (or prints) the PR, stage and commit exactly that path:

```bash
git add .claude/harness-log.jsonl
git commit -m "chore: log this run's checks"
git push
```

This is the run's closing commit — nothing else in this run commits after
it. It has to be its own commit rather than folded into an earlier one:
§3's group commits are scope-checked to that group's own implementation
files only (never the log), and Gates 4-6's writes in §4 land after every
group is already committed — so by the time this step runs there is no
earlier, still-open commit left to fold the log into, and this flow never
amends an already-made commit (see `SKILL.md`'s Exceptions). The `git push` here is a small
follow-up to the one `SKILL.md` §4 step 4 already did — that push
happens before this commit exists, so it can't have carried it. `init-harness`
Step 5 seeds `.gitattributes` with `.claude/harness-log.jsonl merge=union`
(the same treatment `PROGRESS.md` already gets) so two task-group branches
that both appended to the log merge without conflict.

`spec-clarify` (0.5.0) writes this same line shape too, but on its own
timing rather than at `opsx-apply-git`'s PR-open point — it runs before
implementation starts, once per finding, right after the user resolves it
(`gate: "spec-clarify"`, `outcome: "fixed"` or `"deferred"`, never
`"rejected"` — that outcome value only applies to the five gate names above). It
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
  --arg gate "<web-qa|code-review|test-coverage|deep-review|harness-review>" \
  --arg finding "<short description of what the finding was>" \
  --arg outcome "<fixed|rejected|deferred>" \
  --arg ruleNumber "<CR-nn/SR-nn/DR-nn, or empty>" \
  '{ts:$ts,change:$change,kind:"finding",gate:$gate,finding:$finding,outcome:$outcome,ruleNumber:$ruleNumber}')" \
  >> .claude/harness-log.jsonl
```

If `jq` isn't available, construct the equivalent line with `printf`
instead. A failed log write never blocks the run — note it and move on.

## Fields

- `gate` — which of the five gate names above (or `spec-clarify` /
  `spec-review`'s readiness checklist, see above) raised the finding.
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
- `ruleNumber` — optional; the permanent rule code (`agents/code-reviewer.md`,
  `agents/spec-reviewer.md`, or `agents/deep-reviewer.md`) the finding was
  raised under, when the
  raising gate has numbered rules and the finding names one. Empty string
  when it doesn't — `web-qa` and `harness-review` findings have no numbered
  rule to cite yet, and neither does a line written before this field
  existed. A finding without it is still a legal line; nothing downstream
  requires it.

## Why this is a different shape than the other nine lines

This `kind:"finding"` line is deliberately not shaped like the nine
`verdict`-bearing gate-run lines elsewhere in this pipeline. One run can
produce several of these — one per finding — and none of them is a gate run
in its own right, so it carries no `verdict`, `durationMs`, `tokensTotal`,
`model`, `reviewConfidence`, `fixIterations`, or `escalatedToHuman`: those
describe a gate's own execution, not a single finding's fate. `harness-stats`
(`skills/harness-review/references/harness-stats.md`) filters on `kind` to
keep the two record shapes from being summed together.
