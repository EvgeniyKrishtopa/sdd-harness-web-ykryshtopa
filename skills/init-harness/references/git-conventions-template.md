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
