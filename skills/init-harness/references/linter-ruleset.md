# Linter ruleset check

Read this from `init-harness` Step 8c (first-time install and upgrade mode
alike) and from `agents/harness-reviewer.md`'s stack-manifest-drift check.
Both read this same list — it is not duplicated in either place, so a rule
set added or dropped here changes what both report without a second edit.

This is a **recommendation, not a requirement**. It never stops
`init-harness`, never installs a package, and never writes into the
project's linter config or `.claude/harness.json`. A project is free to run
whatever rule sets it wants; this check only makes an already-made choice
visible instead of silent.

## What to check

Look at the project's linter configuration and dependencies for these rule
sets:

| Rule set | When | What is lost without it |
| --- | --- | --- |
| `react-hooks` (`eslint-plugin-react-hooks`) | always | effect dependency arrays and hook-call-order go unchecked — a stale closure or an effect silently missing an update ships until a human notices |
| `jsx-a11y` (`eslint-plugin-jsx-a11y`) | always | missing labels, ARIA roles, and alt text go unchecked — nothing else in this harness's automated checks looks at static accessibility at all |
| `@typescript-eslint` (at least `no-explicit-any`) | always | `any` and unchecked type assertions enter the codebase however far `tsconfig.json` already allows, with nothing narrowing them from there |
| `@next/next` (`@next/eslint-plugin-next`) | only when the detected framework is Next.js | part of what CR-12 (`agents/code-reviewer.md`) covers manually goes unchecked until a review actually runs |

`@next/next` is the one conditional entry: check for it only on Next.js,
never on Vite, and never mention it on a Vite project's report — its absence
there is not a gap, it is not applicable.

## How to report

For each rule set missing from what applies to this project, name it and
the one line above describing what it stops catching. A project with the
full applicable set gets one line saying so — silence here would be
indistinguishable from "not checked."

## When the linter isn't ESLint

Skip the check outright, and say so with one explicit line — `ruleset not
checked: linter isn't ESLint` or equivalent — naming what was skipped and
why. Never let this step disappear into silence: a skipped check that says
nothing reads to a later run exactly like a check that passed.
