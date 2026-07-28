---
name: harness-review
description: Reviews CLAUDE.md/AGENTS.md, .claude/harness.json, .claude/settings.json, .claude/docs/**, and .husky/** for stale claims and drift from authoring best practices — plus this plugin's own skills/ and agents/ when its own repo is what's being reviewed. Use before a final task group's commit, or whenever the harness setup changes.
---

Run **Gate 6** of this project's review pipeline: harness review — the only
gate scoped to the harness configuration itself, not the application code.

## Trigger

The *last* OpenSpec task group with pending tasks, right after Gate 5 (or
Gate 4, if Gate 5 didn't apply) passes — but before that group's own commit.

## Action

Delegate to the `harness-reviewer` subagent (`Agent` tool), scoped to the
paths `init-harness` actually writes into a target repo — `CLAUDE.md`/
`AGENTS.md`, `.claude/harness.json`, `.claude/settings.json`,
`.claude/docs/**`, `.husky/**` — plus `${CLAUDE_PLUGIN_ROOT}/skills/` and
`${CLAUDE_PLUGIN_ROOT}/agents/` only when this plugin's own repo is the one
under review (those two directories live inside the plugin itself; a project
that has merely installed the plugin has no local copy of them to scan).
Name the change so the reviewer can check for anything the change's
implementation should have updated in the harness but didn't — including
whether `.claude/harness.json` still matches reality (e.g. a new script
name, a changed coverage threshold, a package-manager switch) and whether
any skill has grown its own stack re-detection instead of reading that
manifest.

## This gate does not follow the CONFIRMED/PLAUSIBLE pause rule

Harness-review's purpose is suggesting actionable fixes, not just flagging
risk — every finding, either verdict, is shown to the user with its
suggested fix, and the user chooses what to apply. Nothing is silently
auto-applied.

- **A finding the user approves** — apply the fix and commit it as its own
  commit on the group branch (`chore: harness review — <summary>`), *before*
  the group's own implementation commit.
- **Clean, or the user declines every suggestion** — proceed straight to the
  group's own commit.

## Log this gate's run

After the outcome above, append one line to `.claude/harness-log.jsonl` in
the target repo (create the file if it doesn't exist yet) — a plain shell
append, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "-" \
  --arg gate "harness-review" \
  --arg verdict "<clean|plausible|confirmed>" \
  --argjson durationMs <elapsed-ms> \
  --arg model "<model harness-reviewer actually ran on>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, the verdict this run resolved to (`confirmed` if
any finding was raised regardless of whether the user chose to apply it),
the wall-clock time spent, and the model `harness-reviewer` ran on (`group`
is `-`: this gate runs at change scope). If `jq` isn't available, construct
the equivalent JSON line with `printf` instead. A failed log write never
blocks the gate — note it in the report and move on; this is a diagnostic
aid, not part of the pass/fail logic.
