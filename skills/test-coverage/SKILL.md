---
name: test-coverage
description: Reviews a diff for test-coverage gaps and weak assertions against this project's coverage threshold and any acceptance criteria in openspec/. Use after code-review, before merging a behavior change.
---

Run **Gate 5** of this project's review pipeline: test-coverage review.

## Trigger

Gate 4 is clean (or the user explicitly chose to proceed anyway) for a group
whose diff touched application source code or tests. Skipped only when the
group's diff is docs/config-only (no source or test files changed) — a group
that shipped source changes with zero test coverage is exactly the case this
gate exists to catch, not a reason to skip it.

## Read the test runner and threshold from the stack manifest

Read `.claude/harness.json` (written by `init-harness`) for `testRunner` and
`coverageThreshold` — use whichever runner is named to know what a coverage
report looks like and how to run one (`vitest run --coverage` vs
`jest --coverage`), and the recorded threshold rather than a fixed
percentage or a re-read of `vite.config.ts`/`jest.config.*`. If the manifest
is missing, stop and tell the user to run `init-harness` first — see
`${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/stack-detection.md`.

## Action

Delegate to the `test-coverage-reviewer` subagent (`Agent` tool) against the
same diff Gate 4 reviewed, with the detected threshold and acceptance
criteria as context.

## Handling the result

- **CONFIRMED finding** — show it to the user and ask whether to add or fix
  tests now or commit anyway.
- **Clean, or PLAUSIBLE-only** — proceed to Gate 6 if this is the last group
  with pending tasks in the whole change; otherwise commit the group and
  continue the batch (see `opsx-apply-git`).

## Log this gate's run

Whether this gate ran or was skipped (the group touched no tests), append
one line to `.claude/harness-log.jsonl` in the target repo (create the file
if it doesn't exist yet) — a plain shell append, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<group-number>" \
  --arg gate "test-coverage" \
  --arg verdict "<clean|plausible|confirmed|skipped>" \
  --argjson durationMs <elapsed-ms-or-0-if-skipped> \
  --arg model "<model test-coverage-reviewer actually ran on, or empty if skipped>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, the group number, the verdict (`skipped` if the
group touched no tests and the reviewer never ran), the wall-clock time
spent, and the model used. If `jq` isn't available, construct the
equivalent JSON line with `printf` instead. A failed log write never blocks
the gate — note it in the report and move on; this is a diagnostic aid, not
part of the pass/fail logic.
