---
name: test-plan
description: Builds the requirement-to-test coverage table for an OpenSpec change before implementation starts — one row per acceptance criterion, naming the test(s) that close it and its level (unit/integration/end-to-end), never a test-runner name. code-review (Gate 5) later checks written tests against this table instead of judging coverage on impression. Use once a change's artifacts are drafted and reviewed, before opsx-apply-git begins implementing it — "test plan for <change>", "plan tests for <change>", "write the test plan".
---

Build the requirement-to-test coverage table `code-review` later checks
written tests against, before any test is written.

## Trigger

Called by `opsx-propose-review` (its step 8), once the change's artifacts
have passed `spec-review` and before `opsx-apply-git` starts implementing —
and again by `opsx-update-review` (its step 5) whenever a revision changed
an acceptance criterion. Also fine standalone, by change name, to add a plan
to a change that predates this step.

## Action

1. Identify the change (the caller names it; if ambiguous, confirm via
   `AskUserQuestion`).
2. Read `openspec/changes/<change>/proposal.md` for every `FR-`/`NFR-`
   identifier and each of its Given/When/Then acceptance criteria — one row
   per criterion (a Then), not one row per requirement: a requirement with
   three criteria needs three rows, the same granularity `code-reviewer`'s
   CR-06 already matches tests against.
3. For each row, name the test(s) that will close it, in plain language — a
   test file or case doesn't have to exist yet, this plan is written before
   implementation — and a level: **unit**, **integration**, or
   **end-to-end**, never a test-runner name (`vitest`, `playwright`); the
   plan reads the same on a project using either.
4. Every acceptance criterion gets at least one row. A criterion with no
   plan row is either a forgotten test or a criterion that shouldn't have
   been written — name it by identifier in the report, don't skip it
   silently.
5. Read `openspec/changes/<change>/.route` (`opsx-propose-review`'s size
   assessment, session 3). Missing file → treat as `full`, the same
   fallback every other route-aware skill in this plugin uses.
   - **full** → write `openspec/changes/<change>/test-plan.md`: the table
     alone, three columns (requirement ID, tests, level).
   - **short** → insert the same table under a `## Test Plan` heading in
     `proposal.md` itself, rather than a separate file — a short-route
     change already carries fewer documents, and this doesn't add one.
6. Report the table and how many criteria it covers.

## What this skill never does

Never write or run the actual tests — that's implementation, not planning.
Never remove a row because a test later turns out unnecessary; if a
criterion changes or drops, re-run this skill for a fresh plan instead of
hand-editing the table out of sync with the spec it maps.
