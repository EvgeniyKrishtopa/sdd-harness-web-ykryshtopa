# Logging the integration tests from the pre-push note — step 4

Referenced from `SKILL.md` §4 step 4. Background:
`harness-audit/v0.11.0-planned/02-integration-pre-push.txt`.

The integration tests run inside `.husky/pre-push`, where this skill only
sees whether the push went through — not how those tests ended. The hook
can't write the log itself: the log under `.claude/harness-log/` is tracked, and a
line written after the commit would leave the working tree dirty. So the
hook leaves a note in `.claude/.last-pre-push.json` (ignored by git) on
every exit, and this step turns it into a log line
(`${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/git-hooks.md`
step 4).

## Around step 4's push

1. Right before `git push`: `push_start=$(date +%s)`.
2. After it — whether it went through or not — read the note:
   ```bash
   jq -c --argjson s "$push_start" 'select(.ts >= $s)' .claude/.last-pre-push.json 2>/dev/null
   ```
   Empty output (no note, an unreadable one, or one older than this push —
   left by an earlier push, or by a hook written before 0.11.0) → don't
   trust it. If, on top of that, `tests.integration` is set and
   `grep -qF -- "<tests.integration.script>" .husky/pre-push` finds
   nothing, the integration tests never run before a push at all: tell the
   human in one line, on every such run — `integration tests are set up in
   .claude/harness.json, but .husky/pre-push doesn't run them; ask
   init-harness to re-run anyway and add the pre-push block it offers`. The log
   line stays `no fresh hook result`.
3. Write one `gate:"integration"` line (below), whatever the push did. It
   goes into this run's log commit at step 6.2.

The push of the log itself (step 6.2) changes only the log, so the hook
lets it through untested and writes no note — never read the note there.

## The outcome

| Note | `verdict` | `skipReason` / `failureKind` |
| --- | --- | --- |
| no `tests.integration` block | `skipped` | `integration not configured` |
| none fresh (step 2) | `skipped` | `no fresh hook result` |
| `pass` | `clean` | — |
| `fail` | `confirmed` | `failureKind` `app` |
| `services-down` | `confirmed` | `failureKind` `environment` |
| `not-reached` | `skipped` | `earlier link failed` |

`services-down` is not `skipped`: the push stopped, nothing was let past.

When the push failed, tell the human why in one line — `services-down` →
"local services are not running — start them with: `<requires>`"; `fail` →
the integration tests failed (their output is in the push's own output);
otherwise the hook's own last line. Then stop the run, as on any failed
push: don't retry, don't go on to step 5. The log line is already written
and goes out with this run's log commit once the push is repeated.

## The line

```bash
mkdir -p .claude/harness-log
printf '%s\n' "$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" --arg group "<group-number-or-range>" \
  --arg verdict "<clean|confirmed|skipped>" --arg skipReason "<reason, or empty>" \
  --argjson durationMs <the note's durationMs, or 0> \
  --arg failureKind "<app|environment, only for confirmed>" \
  '{ts:$ts,change:$change,group:$group,gate:"integration",verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:0,tokensNote:"",model:"",reviewConfidence:"",fixIterations:0,escalatedToHuman:false,failureKind:$failureKind}')" \
  >> ".claude/harness-log/$(git branch --show-current | sed "s#/#--#g").jsonl"
```

`tokensTotal` is `0`: a shell command, so 0 is the truth here. A failed log
write never blocks the run.
