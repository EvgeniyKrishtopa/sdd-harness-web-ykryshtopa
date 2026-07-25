---
name: harness-review
description: Reviews CLAUDE.md/AGENTS.md, .claude/agents/, .claude/skills/, and .claude/docs/ for stale claims and drift from authoring best practices. Use before a final task group's commit, or whenever the harness setup changes.
---

Run **Gate 6** of this project's review pipeline: harness review — the only
gate scoped to the harness configuration itself, not the application code.

## Trigger

The *last* OpenSpec task group with pending tasks, right after Gate 5 (or
Gate 4, if Gate 5 didn't apply) passes — but before that group's own commit.

## Action

Delegate to the `harness-reviewer` subagent (`Agent` tool), scoped to the
whole harness (`CLAUDE.md`/`AGENTS.md`, `.claude/agents/`, `.claude/skills/`,
`.claude/docs/`), naming the change so the reviewer can check for anything
the change's implementation should have updated in the harness but didn't.

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
