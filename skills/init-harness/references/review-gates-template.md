# Automated Review Gates

AI review is a sensor, not a final verdict — the human owns the merge.
Gates 1, 2, 4, 5 surface findings and pause only on a CONFIRMED finding;
PLAUSIBLE-only or clean reviews never pause anything. Gates 3 and 6 differ
by design (see below).

- **Gate 1 — architecture-review**, after `design.md` is drafted.
- **Gate 2 — spec-review**, after the full artifact set is done. Also
  classifies every `tasks.md` group isolated/judgement-heavy.
- **Gate 3 — web-qa**, on the last group only, if the change touched
  user-facing UI. Must-pass with a fix loop, not CONFIRMED/PLAUSIBLE.
- **Gate 4 + Gate 5 — code-review**, after each group's own verification
  passes: correctness/simplification and test-coverage gaps in one
  delegation (same diff, one spawn) — the coverage section runs whenever the
  group touched source code or tests, and is skipped only for a
  docs/config-only diff. Threshold: {{COVERAGE_THRESHOLD}}% (set at
  `init-harness` time).
- **Gate 6 — harness-review**, on the last group, before its commit. Shows
  every finding with a suggested fix regardless of verdict — nothing is
  silently auto-applied.

Package manager: {{PACKAGE_MANAGER}}. Framework: {{FRAMEWORK}}. Test runner:
{{TEST_RUNNER}}. (Filled in by `init-harness` — do not leave as literal
placeholders in the generated file.)
