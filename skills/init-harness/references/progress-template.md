# `PROGRESS.md` — cold-start continuity

A flat file at the target repo's root, one always-current version — no
history, no append-only log. It exists so a new session's first read answers
what `git log -5` can't: what's already done, what's in progress, what's
blocked and why, and what to do next. The `SessionStart` hook in this
plugin's `hooks/hooks.json` prints its `Status`/`Next steps` sections
automatically at the start of every session (plain shell, 0 model tokens);
this file is where an agent or human reads the rest — clock-in/out history,
the full done list — beyond that digest.

## Who writes it, and when

For the `Current change`/`Status`/`Next steps`/`Session log` sections: only
`opsx-apply-git`, only at **run boundaries** — never per task, never on
every `Stop`:

- §4 step 7 (a run pauses with tasks remaining) — clock-out for this run.
- §5 step 5 (a change is fully archived) — final clock-out for the change.

Both go through one script, `opsx-apply-git/scripts/progress.mjs`
(`clock-out`), never through a free-text or regex edit of the file. Earlier
versions let the model rewrite it each time, and a regex rewrite twice broke
the numbered `Next steps` list — one step vanished, numbering skipped. The
script takes every value as an argument, renumbers the steps itself, keeps
each value on one physical line, leaves sections it doesn't own as they
are, and gives the same file for the same call: running one clock-out twice
changes nothing.

The `Paused changes` section is the one exception to this single-writer
rule — see its own note below.

## Local to this machine (0.12.0)

`PROGRESS.md` is in `.gitignore` and never committed. It answers "where did
I stop" for the next session on this machine, which is all it is for.

Earlier versions committed it, with `merge=union` in `.gitattributes`. That
caused three problems. `merge=union` keeps the lines of both sides — right
for a file that only grows, wrong for one that is rewritten: two `Next
steps` lists would be glued into one, silently. GitHub ignores merge drivers
anyway. And a clock-out left the tracked file modified between runs, so
`git pull` on the parent could refuse to run, and the squash-merge recovery
(`git reset --hard`) would have thrown the clock-out away.

`init-harness` appends `PROGRESS.md` to `.gitignore`. Its upgrade mode also
takes the file out of git on the main branch at once — the file stays on
disk, only git stops tracking it — and merges that into the current branch
(`upgrade-mode.md`, "Taking PROGRESS.md out of git on main"), and removes
the old `merge=union` line.

## Template

```markdown
# Progress

## Current change

- Change: <change-slug, or "none">
- Branch: <branch-name>
- Last commit: <short-hash> — <subject>

## Status

- Done: <groups completed this change, e.g. "1, 2">
- In progress: <group name, or "none">
- Blocked: <group/task — reason, one line (see the `<!-- blocked: ... -->` marker in tasks.md), or "none">

## Next steps

1. <next concrete step>
2. <next concrete step>

## Paused changes

- <change-slug> — paused <YYYY-MM-DD>: <reason, one line>

## PR target

- <parent-branch> → <branch PRs go into> — chosen <YYYY-MM-DD>

## Session log

- Clock-in: <ISO-8601 UTC> — Clock-out: <ISO-8601 UTC>
```

The `Paused changes` section holds a *different* change than the one
`Current change` describes — a whole change set aside to start another,
not a task-level block inside the active one (that's the `Blocked:` line
above, which stays scoped to the current change's own `tasks.md`). Absent
entirely until `opsx-propose-review`'s project-level WIP check (#U5) first
writes to it; omit the heading rather than leaving it empty.

Two skills touch it, each in one direction only, both through
`progress.mjs`: `opsx-propose-review` appends a line (`pause`) when the user
explicitly pauses an unarchived change to start a new one; `opsx-apply-git`'s
`clock-out` removes that change's own line — nothing else in the section —
the next time it reaches a run boundary (§4 step 7 / §5 step 5) *for that
same paused change*, since resuming it implies it isn't paused anymore. Every other regeneration this file undergoes (a run
boundary for whatever change is currently `Current change`, which is a
*different* change than the one being resumed) must leave this section
otherwise untouched, byte-for-byte, the same way `docs/decisions/` is never
touched by anything but a new file: this is the one part of `PROGRESS.md`
that falls outside the single-writer/run-boundary rule above, precisely
because it describes a change that isn't the one currently running.

The `PR target` section is absent until `opsx-apply-git` §1 step 3 finds
a parent that is already merged into the main branch and asks where this
change's PRs should go. `progress.mjs pr-target` writes the answer — one
line per parent, a new answer replaces the old one — so the next run on
that parent follows it without asking again. `clock-out` never touches it.

Keep section headings exactly as shown (`## Current change`, `## Status`,
`## Next steps`, `## Session log`, `## Paused changes`, `## PR target`) — the `SessionStart`
hook locates `## Status`/`## Next steps` by these literal marker strings
with `awk`, not by parsing markdown generally, and `progress.mjs` finds
every section by its heading the same way. Renaming a
heading silently breaks that extraction, with no error to notice it by.
`## Paused changes` isn't part of the `SessionStart` digest itself (same as
`## Current change` and `## Session log` — the hook only ever surfaces
`Status`/`Next steps`); read the file directly for it.

The `In progress:`/`Blocked:` lines and each numbered `Next steps` item must
stay on a single physical line each — the hook's extraction is line-oriented
and cannot reassemble a value that wraps onto a second line; a wrapped
`Blocked:` reason (like the multi-line placeholder above) prints truncated,
silently, with nothing to flag the cut. Write a long reason as one line, even
an unwieldy one.
