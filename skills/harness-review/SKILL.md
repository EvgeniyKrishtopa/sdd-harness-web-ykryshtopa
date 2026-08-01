---
name: harness-review
description: Reviews CLAUDE.md/AGENTS.md, .claude/harness.json, .claude/settings.json, .claude/docs/**, and .husky/** for stale claims and drift from authoring best practices — plus this plugin's own skills/ and agents/ when its own repo is what's being reviewed. Use before pushing a run whose diff touched the harness itself, or whenever the harness setup changes.
---

Run **Gate 6** of this project's review pipeline: harness review — the only
gate scoped to the harness configuration itself, not the application code.

## Trigger

The run covering the *last* OpenSpec task group with pending tasks, right
after `code-review` (Gate 4 + Gate 5, merged into one delegation — see that
skill) passes, whether or not the diff needed the Gate 5 section — every
group in the run is already committed by this point (`opsx-apply-git` §3),
so this runs once per run, not once per group. Also gated by a 0-token
precondition in `opsx-apply-git` §4 step 3 (cost-optimization #35): this
delegation only runs at all if that run's diff touched
`CLAUDE.md`/`AGENTS.md`/`.claude/`/`.husky/`, or `package.json`'s
scripts/dependencies changed. Most runs touch neither and skip this
delegation entirely.

## Action

Read `.claude/harness.json`'s `models.harness` key (written by
`init-harness`) and pass it as the `model` parameter when delegating to the
`harness-reviewer` subagent (`Agent` tool) — overriding the agent's own
frontmatter default for this run. If the manifest or the key is missing,
fall back to the agent's own default; never block the gate on a missing
override. Scope the review to the
paths `init-harness` actually writes into a target repo — `CLAUDE.md`/
`AGENTS.md`, `.claude/harness.json`, `.claude/settings.json`,
`.claude/docs/**`, `.husky/**` — plus `${CLAUDE_PLUGIN_ROOT}/skills/` and
`${CLAUDE_PLUGIN_ROOT}/agents/` only when this plugin's own repo is the one
under review (those two directories live inside the plugin itself; a project
that has merely installed the plugin has no local copy of them to scan).
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` is also in scope — it is
the other half of checklist item 6's version comparison, and reading it is
how the reviewer tells "the plugin was updated but this repo wasn't" from
"up to date". That comparison needs both halves, so it doesn't run when the
repo under review has no `.claude/harness.json` of its own (this plugin's
own repo, for one); the agent reports that it couldn't run rather than
reporting a match.
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
  commit on the run's branch (`chore: harness review — <summary>`). Every
  group in the run is already committed by this point, so there's no
  ordering constraint forcing this ahead of a group's own commit — it
  simply lands as the next commit before push.
- **Clean, or the user declines every suggestion** — proceed straight to
  push.

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
is `-`: this gate runs at change scope). A fourth verdict value,
`skipped`, also appears under `"gate":"harness-review"` in this log — but
is written by `opsx-apply-git` itself, not by this agent, when its Gate 6
precondition finds nothing to review and this delegation never runs at all
(cost-optimization #35). If `jq` isn't available, construct the equivalent
JSON line with `printf` instead. A failed log write never
blocks the gate — note it in the report and move on; this is a diagnostic
aid, not part of the pass/fail logic.
