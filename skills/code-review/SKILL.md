---
name: code-review
description: Reviews a task group's uncommitted diff for correctness bugs and reuse/simplification/efficiency cleanups against this project's standards. Use --fix to apply findings. Run before every group's commit and before merging any change.
---

Run **Gate 4** of this project's review pipeline: code review.

## Trigger

Every sub-task in an OpenSpec task group is implemented and the group's own
verification (typecheck/lint/tests, per the group's tasks) passes — after
the diff-scope check and, on the last group, after Gate 3 (web-qa) has
passed or been ruled not applicable.

## Action

1. Run `git diff --stat` and `git diff` against the group's uncommitted
   changes (including any web-qa fixes Gate 3 introduced on the last group).
2. Delegate to the `code-reviewer` subagent (`Agent` tool) with that diff.
3. If invoked as `/code-review --fix`, apply the findings the subagent
   suggests once the user confirms which ones.

## Handling the result

- **CONFIRMED finding** — show it to the user and ask whether to fix now or
  commit anyway. Do not auto-commit past an unresolved CONFIRMED finding.
- **Clean, or PLAUSIBLE-only** — proceed to Gate 5.

## Log this gate's run

After delivering the verdict above, append one line to
`.claude/harness-log.jsonl` in the target repo (create the file if it
doesn't exist yet) — a plain shell append, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<group-number>" \
  --arg gate "code-review" \
  --arg verdict "<clean|plausible|confirmed>" \
  --argjson durationMs <elapsed-ms> \
  --arg model "<model code-reviewer actually ran on>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, the group number this run reviewed, the verdict
this run resolved to, the wall-clock time spent from delegating to
`code-reviewer` to receiving its response, and the model it actually ran on.
If `jq` isn't available, construct the equivalent JSON line with `printf`
instead. A failed log write never blocks the gate — note it in the report
and move on; this is a diagnostic aid, not part of the pass/fail logic.
