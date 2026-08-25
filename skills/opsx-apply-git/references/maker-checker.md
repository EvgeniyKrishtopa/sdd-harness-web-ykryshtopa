# The maker-checker split — tests written by a different actor

Loaded by `SKILL.md` §3 only when `.claude/harness.json` has
`makerChecker.enabled: true` **and** the group being implemented has at
least one test-plan row for the requirement identifiers its tasks name. A
docs-only or config-only group has none and does not pay for a subagent that
would have nothing to write.

## Why the tests come first

An author who has read the implementation writes tests it passes by
construction. "Don't look at it" cannot be enforced on an agent that can
read the repository — writing the tests before the code exists is what
actually enforces it.

And the failure this catches is one nothing else in the pipeline looks for:
a test written by the author of the code proves the code does what its
author meant. When the author misread the requirement, the test preserves
the misreading — it exists, it names the right requirement, it passes, and
Gate 5 is satisfied. What diverged is the test and the requirement.

## The procedure

1. **Before writing any of this group's code**, delegate to the
   **`test-author`** agent (`Agent` tool, `model` from
   `models.testAuthor`, falling back to the agent's own default). Hand it:
   the group's tasks with their requirement identifiers, the matching rows
   of `test-plan.md` (or `proposal.md`'s `## Test Plan` section), and those
   identifiers' Given/When/Then criteria. It writes the tests, runs them,
   and reports each one red.

2. **Record what it left**, so a later edit is detectable rather than
   remembered:

   ```bash
   hashes="$(git rev-parse --git-dir)/tmp-test-author-hashes"
   git status --porcelain -- '*test*' '*spec*' | awk '{print $2}' \
     | xargs -r shasum > "$hashes"
   ```

   `.git/` keeps the file out of the working tree, so no stray file can be
   committed with the group.

3. **Implement the group's code until those tests pass. Do not edit the
   tests.** Not to fix an import, not to relax an assertion, not to correct
   what looks like an obvious mistake in them.

4. **Before committing the group, re-hash the same files and compare.** Any
   difference → stop and ask the human, naming the file and what changed.
   Two outcomes, and it is not yours to pick:

   - the test misreads the requirement → `test-author` rewrites it, not you;
   - the requirement itself reads two ways → the spec is what changes.

   Delete `$hashes` on every exit path — the stop above included — the same
   cleanup rule `SKILL.md` §4's diff file follows.

A test that turns out to be impossible to satisfy is the same stop, not a
licence to edit: bound the attempts by `maxFixAttempts`, as everywhere else,
then hand it to the human.

## What does not change

Gate 5 still checks the written tests against the plan afterwards
(`CR-06`…`CR-09`, and `CR-13` for the level). This split runs before it and
does not replace it: one decides who writes the tests, the other whether
what was written closes the plan.
