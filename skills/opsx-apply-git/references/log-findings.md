# Logging CONFIRMED findings — point 7

Referenced from `SKILL.md` §4 step 6. Background:
`harness-audit/v0.4.0-implemented/03-log-fields.txt` point 7.

The nine `verdict`-bearing lines this pipeline already writes to
the log (one per gate, plus `opsx-apply-git`'s own two
skip forms) record what a gate *said*. None of them record whether that
verdict held up — whether a CONFIRMED finding was actually fixed, or the
human looked at it and moved on, or it never got resolved at all. Without
that, a noisy gate and a trustworthy one look identical in the log.

Two line shapes in the log carry a `kind` field and no `verdict`: this
file's `kind:"finding"`, and `web-qa`'s `kind:"web-qa-flows"` (0.11.0 —
`recordedFlows`, `declinedFlows`, `failureKind`; see
`skills/web-qa/references/log-fields.md`). Anything that counts gate runs
counts only lines without `kind`.

Besides the nine verdict lines above, two test steps write verdict lines
of their own: the replay of recorded scenarios before push (§4 step 3a,
`references/e2e-replay.md`), `gate:"e2e-replay"`, with three more fields —
`scope`, `scopeReason`, `scenarios`; and the integration tests in
`.husky/pre-push` (§4 step 4, `references/pre-push-note.md`),
`gate:"integration"`. Neither is a numbered gate: their skip reasons are
their own, not part of the list in "Checks" below, and the Checks part
stays six lines.

**`failureKind`** (0.11.0) — on `e2e-replay`'s and `integration`'s verdict lines: `app` when
the code failed, `environment` when a check stopped before the code was
ever tried (the environment check, `testDir` not covering the scenarios, no
server to connect to, local services not running). Set only when the verdict is `confirmed`, empty
otherwise. `web-qa`'s flows line carries the same field, with `environment`
as its only value. An `environment` failure
never goes through `debug-loop`, so its `fixIterations` is `0`.

## When to write this

At the point `SKILL.md` §4 step 6 already forms the run's summary — not
earlier, at the moment each finding is raised. Track each CONFIRMED finding
and its resolution as the run goes (across Gates 3-6: `web-qa`,
`code-review`, `test-coverage`, `deep-review`, `harness-review` — plus
`e2e-replay`, one finding per red scenario), then write one line per
finding here, right before opening the PR. A run with no CONFIRMED findings
writes nothing — this section only exists for findings serious enough to
have been CONFIRMED, not for every PLAUSIBLE note.

This same tracked list also feeds the PR's "Review trail" section below —
collected once, as the run goes, and read back for both destinations. Never
re-derive it a second time by re-reading the log: it
can hold `kind:"finding"` lines from earlier runs of the same `change`
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
   { awk 1 .claude/harness-log.jsonl; find .claude/harness-log -name '*.jsonl' -exec awk 1 {} +; } 2>/dev/null \
     | jq -R "fromjson?" | jq -sc --arg change "<change-slug>" --arg gate "<gate-name>" \
       '[.[] | select(.change == $change and .gate == $gate and has("verdict"))]
        | sort_by(.ts) | last // empty'
   ```
   A `skipped` verdict always carries one of the closed-list reasons already
   written elsewhere in this pipeline — `UI not touched`, `docs only`,
   `small change`, `harness config unchanged`, or `no risk signals` — print
   it verbatim next to the verdict. A log written before 0.10.2 carries the
   same reasons in Russian; print those verbatim too. No matching line for a gate → say
   so on that gate's line rather than omitting it.
3. **Findings** — this run's CONFIRMED findings from the tracked list above:
   rule number, one-line description, outcome. PLAUSIBLE notes never appear
   here. More than ten → print the first ten and one closing line, "...and
   `<N>` more, see `.claude/harness-log/`." No CONFIRMED findings →
   one explicit line saying so; never omit this part.
4. **Deferred** — one line per entry currently under `proposal.md`'s
   `## Open Questions` heading, verbatim (owner and due date are already
   part of that line's format — see `spec-clarify`), then one line per
   open entry under this change's `## <change-slug>` heading in
   `docs/deferred.md`, linking to that entry (`deferred-log.md`, "Reading it
   for the PR body"). Neither source has anything → one explicit line
   saying so.

This section is assembled entirely from data this pipeline already writes
elsewhere — this run's own gate verdicts, the findings list above,
`proposal.md`'s Open Questions, and `docs/deferred.md`. It never introduces a new
log field to answer a question the log doesn't
already record.

## Where the log lives (0.12.0)

One file per branch: `.claude/harness-log/<branch>.jsonl`, where
`<branch>` is `git branch --show-current` with every `/` turned into `--`
(`feature/add-login-2` → `feature--add-login-2.jsonl`). Every writer in this
plugin appends with the same two lines, so the name never drifts:

```bash
mkdir -p .claude/harness-log
printf '%s\n' "<line>" >> ".claude/harness-log/$(git branch --show-current | sed "s#/#--#g").jsonl"
```

Before 0.12.0 every branch appended to one shared `.claude/harness-log.jsonl`,
kept mergeable by `merge=union` in `.gitattributes`. That works for a local
`git merge`, but GitHub ignores merge drivers: two group PRs that both
appended to the file showed as conflicting, and resolving it in the web UI
could commit to a protected branch. Two branches never write the same file
now, so there is nothing to conflict on.

**Reading the log** means reading every file in the folder plus the old
file, which a project upgraded from an earlier version still has and which
is never moved or deleted:

```bash
{ awk 1 .claude/harness-log.jsonl; find .claude/harness-log -name '*.jsonl' -exec awk 1 {} +; } 2>/dev/null
```

`awk 1`, not `cat`: it adds a missing final newline, so a file that ends
without one can't glue its last line to the next file's first. Lines from
different files are not in time order — sort by `ts` when order
matters ("the latest line for this gate"). The `find` form, not a
`.claude/harness-log/*.jsonl` glob, because zsh aborts the whole command on
a glob that matches nothing.

## Committing the log (point 4)

`SKILL.md` §4 step 6.2 commits the log right after this run's Review trail
section is composed and before step 6.3 opens (or prints) the PR:

```bash
git add .claude/harness-log/
git commit -m "chore: log this run's checks"
git push
```

The whole folder, not only this branch's file: `architecture-review`,
`spec-review` and `spec-clarify` write their lines while the parent branch
is checked out, into the parent's file, and nothing commits them there. The
first run's log commit carries them, as it carried them when the log was one
file.

This is the run's closing commit — nothing else in this run commits after
it. It has to be its own commit rather than folded into an earlier one:
§3's group commits are scope-checked to that group's own implementation
files only (never the log), and Gates 4-6's writes in §4 land after every
group is already committed — so by the time this step runs there is no
earlier, still-open commit left to fold the log into, and this flow never
amends an already-made commit (see `SKILL.md`'s Exceptions). The `git push` here is a small
follow-up to the one `SKILL.md` §4 step 4 already did — that push
happens before this commit exists, so it can't have carried it.

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
mkdir -p .claude/harness-log
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg gate "<web-qa|code-review|test-coverage|deep-review|harness-review|e2e-replay>" \
  --arg finding "<short description of what the finding was>" \
  --arg outcome "<fixed|rejected|deferred>" \
  --arg ruleNumber "<CR-nn/SR-nn/DR-nn, or empty>" \
  '{ts:$ts,change:$change,kind:"finding",gate:$gate,finding:$finding,outcome:$outcome,ruleNumber:$ruleNumber}')" \
  >> ".claude/harness-log/$(git branch --show-current | sed "s#/#--#g").jsonl"
```

If `jq` isn't available, construct the equivalent line with `printf`
instead. A failed log write never blocks the run — note it and move on.

## Fields

- `gate` — which of the five gate names above, or `e2e-replay` (or `spec-clarify` /
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
