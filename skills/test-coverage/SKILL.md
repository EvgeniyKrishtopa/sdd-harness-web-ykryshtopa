---
name: test-coverage
description: Reviews a diff for test-coverage gaps and weak assertions against this project's coverage threshold and any acceptance criteria in openspec/. Use after code-review, before merging a behavior change.
---

Run **Gate 5** of this project's review pipeline: test-coverage review.

## Trigger

Gate 4 is clean (or the user explicitly chose to proceed anyway) for a group
whose tasks included test creation or updates. Skipped entirely if the group
touched no tests.

## Detect the test runner and threshold before reviewing

1. Check `package.json` devDependencies for `vitest` or `jest` — use
   whichever is present to know what a coverage report looks like and how
   to run one (`vitest run --coverage` vs `jest --coverage`).
2. Read the coverage threshold from this project's config (`vite.config.ts`
   `test.coverage.thresholds`, or `jest.config.*` `coverageThreshold`, or
   `.harness/config.json` if `init-harness` wrote one — see that skill).
   Never assume a fixed percentage; the threshold is per-project, set at
   `init-harness` time.

## Action

Delegate to the `test-coverage-reviewer` subagent (`Agent` tool) against the
same diff Gate 4 reviewed, with the detected threshold and acceptance
criteria as context.

## Handling the result

- **CONFIRMED finding** — show it to the user and ask whether to add or fix
  tests now or commit anyway.
- **Clean, or PLAUSIBLE-only** — proceed to Gate 6 if this is the last group
  with pending tasks in the whole change; otherwise commit the group and
  continue the batch (see `opsx-apply-git`).
