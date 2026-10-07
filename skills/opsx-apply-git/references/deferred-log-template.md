# `docs/deferred.md` — the template

`references/deferred-log.md` says when this file is written. This file holds
what gets written: the header that goes at the top of a new
`docs/deferred.md`, and the shape of one entry.

The path is fixed: `docs/deferred.md` in the target project, with no
`.claude/harness.json` key. A key would be added only when a real project
needs a different path.

## The header

Write everything inside the fence below, verbatim, when the file doesn't
exist yet. Never rewrite the header of a file that already exists, even if
its wording differs from this one: the project may have written its own.

````markdown
# Deferred items

Spec points that a finished task group did **not** fully deliver: blocked, skipped by decision, or no longer relevant. Each one is recorded here so it outlives `openspec archive`, which moves the change folder and its `tasks.md` out of sight.

The path is fixed at `docs/deferred.md`; `opsx-apply-git` reads and writes it here and has no setting to move it.

## When to add an entry

At the end of every task group, before the group's commit, add an entry for each task or acceptance criterion that ends the group in one of these states:

- **blocked**: still carries `<!-- blocked: … -->` in `tasks.md`.
- **skipped**: checked, but part of its verification was waived by a human decision. The agent never waives verification on its own.
- **obsolete**: no longer relevant because the requirement changed or the approach was replaced, by a human decision.

The task line stays in `tasks.md`. `opsx-apply-git` reads its checkbox and `blocked` marker to pick the next run and to decide when to archive, so only a short pointer is added to the line: `<!-- deferred: docs/deferred.md -->`. The reasoning lives here, not in the comment.

Entries are grouped under one `## <change-slug>` heading per change. When the change is archived, a line `Archived at openspec/changes/archive/<date>-<change-slug>/` is added under that heading.

## How to resolve an entry

When a later change delivers the point, a blocked task is unblocked and ticked, or the risk is formally accepted, set **Status** to `resolved (<change or decision>)`. Resolved entries stay in the file as history and are not deleted.

## Entry format

```md
### <change-slug> · <task id> — <short title>

- **State:** blocked | skipped | obsolete
- **Requirement:** <FR-/NFR- ids>
- **What is missing:** <the part not verified or delivered>
- **Why:** <reason>
- **Verified instead:** <what was checked, or "nothing">
- **Decision:** <who, date>
- **Status:** open | resolved (<change or decision>)
```

---
````

## Field notes

- **Task id** is the number on the task line in `tasks.md` (`4.2`). For an
  acceptance criterion that isn't its own task, use the criterion's id
  (`AC3`).
- **Requirement** is `-` when the task names no `FR-`/`NFR-` id.
- **Decision** for a blocked entry names whoever stopped the work:
  `opsx-apply-git, <date>: run stopped` when the run stopped on its own,
  the human's name or "user" when they called it.
- **Status** starts with `open` or `resolved`. Text after that word is
  allowed (`open. Natural place to close it is the deploy step`), so read
  only the first word to tell open from resolved.
