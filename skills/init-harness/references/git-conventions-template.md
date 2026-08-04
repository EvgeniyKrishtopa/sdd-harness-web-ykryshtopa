# Git Conventions

## Branch naming

`<type>/<short-description>` where `type` is one of `feature`, `fix`,
`chore`, `refactor`. One branch per OpenSpec change (parent), plus one
short-lived branch per task group or isolated batch (see `opsx-apply-git`).

## Commit messages — Conventional Commits

`<type>(<scope>): <summary>`, body covering what changed, why, how it was
validated (each gate's outcome), and remaining risks.

## OpenSpec task granularity

Commit once per numbered group in `tasks.md`. One group = one branch = one
session boundary for `opsx-apply-git`. This explicitly overrides the general
"never commit without being asked" default, but only at group/archive
boundaries — nowhere else.

## AI commit discipline

Every commit an agent makes documents: what changed, why, how it was
verified (gate outcomes, test results), and known remaining risk. Never
`--no-verify` past a failing pre-commit or pre-push hook — fix the root
cause instead.

## Project-level WIP=1

`opsx-apply-git` already keeps WIP=1 *within* a run (one run per invocation,
never chained in the same session). Nothing enforced it *across* runs: do
not start `openspec propose` for a new change while a previous one is still
unarchived, unless it's been explicitly paused with a reason recorded in
`PROGRESS.md` — otherwise the project drifts into either overreach (several
changes started, none finished) or under-finish (code everywhere, green
nowhere). `opsx-propose-review` checks this deterministically and asks
before proceeding; it never blocks outright.

**VCR (Verified Completion Rate)**: `passing ÷ (passing + blocked)` — tasks
marked `- [x]` divided by tasks that have actually been started (`- [x]` plus
`<!-- blocked: ... -->`, #U4). Not started (`- [ ]`, no marker) doesn't count
in either the numerator or the denominator. Computed by hand or by
`harness-stats` (#U14) — no separate mechanism for it in this release.
