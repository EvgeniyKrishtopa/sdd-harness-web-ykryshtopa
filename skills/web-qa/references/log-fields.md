# The web-qa log lines — what goes in each field

Read from `SKILL.md` "Log this gate's run".

## The verdict line

Fill in the change slug, `verdict` as `clean` for all-PASS, `confirmed` for
any FAIL found along the way (even if later fixed and re-passed), or
`skipped` when this gate wasn't applicable; the wall-clock time across the
whole fix loop; and the model `web-qa-manual-tester` ran on (`group` is `-`:
this gate covers the whole change, triggered on the last group). `skipReason`
is the closed-list reason matching this gate's own applicability check —
`UI not touched` exactly when `verdict` is `skipped`, empty
otherwise. Also fill in its stated `reviewConfidence`, empty when skipped.
`tokensTotal` is the `subagent_tokens` figure from the `<usage>` block the
environment appends after the `web-qa-manual-tester` delegation returns
(point 5, `harness-audit/v0.4.0-implemented/03-log-fields.txt`), `0` when
skipped — never estimate it from a proxy.
Write the line only once `<usage>` has arrived — a background delegation
reports first. If it never arrives, `tokensTotal` is `null` and
`tokensNote` says why; never `0`, which `harness-stats` reads as a free run.
`fixIterations` is the attempt count `debug-loop` itself reports back (phase
4's "report success and the number of attempts it took"), summed if more
than one flow needed its own invocation this run; `0` when every flow
passed on the first try or the gate was skipped. `escalatedToHuman` is
`true` only if `debug-loop` reached `maxFixAttempts` on this run without
resolving a failure — the same run that then wrote a `blocked` marker
instead of proceeding. If `jq`
isn't available, construct the equivalent JSON line with `printf` instead.
A failed log write never blocks the gate — note it in the report and move
on; this is a diagnostic aid, not part of the pass/fail logic.

## The flows line (0.11.0)

Right after the verdict line, whenever the gate ran (not when it was
skipped), append one more line — its own shape, like `opsx-apply-git`'s
`kind:"finding"` line, so the nine verdict lines keep one field set:

```bash
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --argjson recordedFlows '<[{"flow":"<name>","file":"<scenariosDir>/<flow-slug>.spec.ts"}, ...] or []>' \
  --argjson declinedFlows '<["<name>", ...] or []>' \
  --arg failureKind "<environment, when the environment check stopped the gate; empty otherwise>" \
  '{ts:$ts,change:$change,kind:"web-qa-flows",gate:"web-qa",recordedFlows:$recordedFlows,declinedFlows:$declinedFlows,failureKind:$failureKind}')" \
  >> .claude/harness-log.jsonl
```

`recordedFlows` and `declinedFlows` come from "Propose recording" step 1's
per-flow answers; `code-review` reads them so it never reminds the human
about a flow they already decided on. Both empty and `failureKind` empty is
a real line, not one to leave out: it says this gate ran and recorded
nothing. The same failed-write rule as the verdict line applies.
