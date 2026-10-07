# `docs/deferred.md` — the log that outlives `openspec archive`

Read this before any commit that finishes a group, writes a `blocked`
marker, or archives a change. `openspec archive` moves the change folder,
and with it `tasks.md`'s `blocked` markers and notes, out of sight. This log
lives in `docs/`, so an open point stays visible after the archive.

The header and entry format are in `references/deferred-log-template.md`.

## The three writes

### 1. A group ends with a task not fully delivered

Before the commit that carries the group's task-line changes, look at every
task line the run touched in that group. A task ends the group in a
deferred state when:

- **blocked**: it carries `<!-- blocked: … -->`. This includes the
  standalone marker commit from `references/blocked-tasks.md`: the entry
  goes into that same commit.
- **skipped**: it is checked, and the human said in this session that part
  of its verification can be waived. Never record "skipped" for a check the
  agent decided to drop. If the agent can't verify something, that is a
  pause and a `blocked` marker, not a skip.
- **obsolete**: the human said the task or criterion no longer applies.
  How the task line itself changes is the human's call; this step only
  records it.

For each such task:

1. If `docs/deferred.md` doesn't exist, create it from the template's
   header. Never create it when the group has nothing to record: a group
   that finishes clean doesn't create or touch the file.
2. Find the `## <change-slug>` heading. If it's missing, append it at the
   end of the file, after a blank line.
3. Find the entry whose heading starts with `### <change-slug> · <task id> —`
   and has the same short title. Found → update its fields in place. Not
   found → append a new entry at the end of that change's section, in the
   template's format.
4. Add ` <!-- deferred: docs/deferred.md -->` to the end of the task line,
   once. Leave the checkbox, the `blocked` marker, and the rest of the line
   exactly as they are: §3 reads them to pick the next run, and §5 reads
   them to decide when to archive.
5. Stage `docs/deferred.md` by its explicit path with the rest of that
   commit.

### 2. A blocked task is unblocked and ticked

When a group's commit includes a task line that is now `- [x]`, has no
`blocked` marker, and carries the `deferred` pointer, find its entry and
set **Status** to `resolved (<what closed it>)`: this change and group
(`resolved (<change-slug>, group 4)`) or the human's decision. Keep the
entry and the pointer; resolved entries are history. Stage the file with
that commit.

### 3. The change is archived

In §5, after `openspec archive` and before the `chore: archive` commit: if
`docs/deferred.md` has a `## <change-slug>` heading, add one line right
under it:

```
Archived at `openspec/changes/archive/<date>-<change-slug>/`.
```

Take the real folder name from `ls openspec/changes/archive/`. Leave every
entry's Status as it is: an open entry stays open after the archive, which
is the reason this file exists. Include the file in the archive commit. No
heading for this change → don't touch the file.

## Reading it for the PR body

`references/log-findings.md` point 4 (Deferred) lists this change's open
entries: every `###` entry under `## <change-slug>` whose Status starts with
`open`. One line each:

```
- <task id> — <short title> (<state>): [docs/deferred.md](docs/deferred.md#<anchor>)
```

`<anchor>` is GitHub's heading id: lower-case the heading text, drop every
character that isn't a letter, digit, space, `-` or `_`, then turn each
space into `-`. `add-ci-pipeline · 4.2 — TypeScript 7 upgrade held` becomes
`add-ci-pipeline--42--typescript-7-upgrade-held`. For a heading that occurs
twice in the file, GitHub adds `-1` to the second one. With `forge:
"other"`, print the file path and the heading text instead of a link.

## An existing file

A project may already keep `docs/deferred.md` by hand. Append to it and
update only the entries this change owns. Never reformat, reorder, or
rewrite its header or other changes' sections, even where they differ from
the template.
