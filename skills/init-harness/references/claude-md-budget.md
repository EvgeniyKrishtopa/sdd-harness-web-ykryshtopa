# The root instruction file's line budget

This is the one place the budget is stated. `init-harness` (Steps 9 and 10)
and `harness-reviewer` (check 2) both point here.

## The budget: 100 lines

`CLAUDE.md` (or `AGENTS.md`, when the project uses that instead) is loaded
into every session. Past about 100 lines, rules that matter only for one
kind of work (styling, testing, environment variables) crowd out the ones
that matter every time. The `BUDGET` value in `scripts/claude-md-lines.sh`
must match this number; `tests/claude-md-budget.sh` checks that it does.

## How to count

Run `../scripts/claude-md-lines.sh` (relative to this file) from the repo
root; never estimate. The skill or agent that sent you here gives its full
path. With no argument it counts `CLAUDE.md`, or `AGENTS.md` when there is
no `CLAUDE.md`.

It prints two numbers, and a report always shows both:

- **Root**: the file's own lines. This is the number checked against the
  budget.
- **Effective**: root plus every file it `@`-imports, followed up to five
  hops, each file counted once. An `@`-import is loaded in full, so it is
  not progressive disclosure. This number is information only: it shows
  what a session actually pays for, and no finding is raised on it alone.

The harness pointer block (`claude-md-pointer-template.md`) imports some of
`.claude/docs/*.md`, `CONTEXT.md` and `.claude/harness.json`. List those in
the effective count like any other import. Don't propose turning them into
plain links: that is the plugin's call, not the project's.

## Over budget: the split proposal

When root is over 100 lines, propose a split. Never apply it: the file is
the user's. It changes only after the human approves, and then only as
proposed.

1. **Deletion Test first.** For every rule, ask: if this line were
   deleted, would Claude actually start making mistakes in this project? A
   rule that traces to a real incident or a hard constraint passes. Delete
   the ones that fail before moving anything. A deleted line beats a moved
   one.
2. **What stays in the root.** Content that matters in every session:
   stack, commands, shell rules, hard "always" rules, the harness pointer
   block, and the "Read when relevant" table itself.
3. **What moves.** Each section that matters only for one kind of work
   moves to `docs/<topic>.md` (not `.claude/docs/`, which the harness
   owns). Name the section, its line range, and the target file.
4. **Each moved file gets a table row with a specific trigger.** "Before
   writing or changing component styles" is a trigger; "for more info" is
   not. If no specific trigger fits, the content should be deleted, not
   moved. The table goes in the root under its own heading:

   ```markdown
   ## Read when relevant

   Not auto-loaded — open the file before doing the matching kind of work.

   | Doc | Read before… |
   | --- | --- |
   | `docs/styling.md` | writing or changing component styles |
   | `docs/testing.md` | writing or moving tests, coverage questions |
   ```

   Link the file in the table; never `@`-import it, or it is loaded in
   every session again.
5. **The result.** The root's line count after the split, which must be
   within the budget.

The proposal has this shape:

```
CLAUDE.md: 130 lines, budget 100. Effective with @-imports: 410.
Delete: <line or rule> — <why it fails the Deletion Test>
Keep in root: Stack, Commands, Shell, Always, Harness block
Move: "## Styling" (lines 40-62) → docs/styling.md
Move: "## Testing" (lines 63-80) → docs/testing.md
Table rows:
| `docs/styling.md` | writing or changing component styles |
| `docs/testing.md` | writing or moving tests, coverage questions |
After the split: 88 lines.
```

At or under 100 lines: no size finding. Report both numbers in one line
and move on.
