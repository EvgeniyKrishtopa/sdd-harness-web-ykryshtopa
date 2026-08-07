# `dead-code-report.md` structure

Write the report to `dead-code-report.md` at the repo root, overwriting
whatever was there from the previous run. A fixed path that gets overwritten
— not a new timestamped file each time — is deliberate: it's what makes
`git diff dead-code-report.md` between two runs show exactly what's new and
what got resolved, which is the whole point of running this more than once
(see SKILL.md, "Why the report is one file, overwritten each run").

```markdown
# Dead Code Report — <YYYY-MM-DD>

<!-- Only on this project's first-ever run of this command: -->
**First run on this project.** This is a baseline, not a deletion list —
see "First run vs. later runs" below before treating Group 1 as an action
item.

## Summary

- Group 1 (reliable): <N> findings
- Group 2 (needs a look): <N> findings
- Group 3 (can't prove): <N> findings
- Rejected this run: <N> (recorded in the knip config, see below)

## Group 1 — Reliable

Unreferenced anywhere, not on a framework-reserved path, passed the step-3
string search with no hits. Safe to hand to `opsx-propose-review` as its own
isolated task group.

For each finding:

- `<path or package name>`
- Source: knip / linter rule `<rule-id>`
- What it reported: `<one line>`

## Group 2 — Needs a look

Referenced only from tests, Storybook, or config; or a commented-out block
the heuristic search found. Judgement-heavy — a human decides per item.

For each finding, same fields as Group 1, plus:

- Where the only remaining reference lives (e.g. `*.test.ts`, `.storybook/`)

## Group 3 — Can't prove

Matches one of `references/false-positives.md`'s shapes, or step 3's string
search found a hit. Listed for awareness, not for action — do not propose
deleting these without independent confirmation outside this report.

For each finding, same fields as Group 1, plus:

- Why it landed here: `<false-positive shape, or "string reference found at
  <file>:<line>">`

## Rejected this run

Findings the human declined to act on, now recorded in the knip config via
`scripts/record-rejection.sh` so they stop reappearing:

- `<path or name>` — `<reason>`

## First run vs. later runs

A first run on any project is a baseline, not a deletion list: a fresh
project's `Group 1` typically lists scaffolding and libraries added ahead of
code that hasn't been written yet. The value of this report is in the
*diff* between runs, starting with the second one — say this in the
report itself whenever it's the first run, since a first report read as
"noisy" is the reason a second one never happens.

## Next step

Turn Group 1 into its own isolated task group in a new change via
`opsx-propose-review`; put Group 2 and Group 3 items into judgement-heavy
groups, one per finding or small related batch. This report is a draft, not
an OpenSpec artifact — the usual process (branch, commits, checks before
push) takes over from here. This command does not delete anything itself.
```
