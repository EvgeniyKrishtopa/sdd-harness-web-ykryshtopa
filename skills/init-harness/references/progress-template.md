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

Only `opsx-apply-git`, only at **run boundaries** — never per task, never on
every `Stop`:

- §4 step 7 (a run pauses with tasks remaining) — clock-out for this run.
- §5 step 5 (a change is fully archived) — final clock-out for the change.

One entry per PR, not per task-group inside a batch. Never let a model
rewrite this file in free-form prose on every turn — that's tokens spent on
every step, a growing source of noise, and (per the merge note below) a
conflict manufactured on every group's branch instead of once per run.

## Merge safety

This harness uses branch-per-group: several group branches fork from the
same parent and merge back into it in sequence. `PROGRESS.md` is the one
file every one of those branches can legitimately touch — without help, that
means a merge conflict on every single PR. `init-harness` writes
`.gitattributes` with `PROGRESS.md merge=union` to make concurrent edits
concatenate instead of conflict. This is the *only* file in this harness that
carries `merge=union` — `docs/decisions/` doesn't need it, because two
branches recording two different decisions produce two different files, not
contending edits to one.

## Self-checking generation

Don't trust a single write. After (re)generating the file, re-read it back
and reconcile it against the actual source of truth — `tasks.md`'s checkbox
and `<!-- blocked: ... -->` state, `git log -1` for the last commit — and
fill in anything the first pass missed before moving on. Two or three lines
of verification, not a second full rewrite; the goal is a file that survives
a partial or interrupted write, not a perfect first draft.

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
- Blocked: <group/task — reason (see the `<!-- blocked: ... -->` marker in
  tasks.md), or "none">

## Next steps

1. <next concrete step>
2. <next concrete step>

## Session log

- Clock-in: <ISO-8601 UTC> — Clock-out: <ISO-8601 UTC>
```

Keep section headings exactly as shown (`## Current change`, `## Status`,
`## Next steps`, `## Session log`) — the `SessionStart` hook locates them by
these literal marker strings with `awk`, not by parsing markdown generally.
Renaming a heading silently breaks the hook's extraction, with no error to
notice it by.
