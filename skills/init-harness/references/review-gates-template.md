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
- **Gate 4 + Gate 5 — code-review**, once per run: correctness/
  simplification and test-coverage gaps in one delegation (same diff, one
  spawn). For a judgement-heavy run this is that one group's diff; for an
  autonomous isolated batch it's the whole batch's cumulative diff, reviewed
  once after every group in the batch is already committed, not once per
  group. The coverage section runs whenever the run touched source code or
  tests, and is skipped only for a docs/config-only diff. Threshold:
  {{COVERAGE_THRESHOLD}}% (set at `init-harness` time). A 0-token
  pre-filter skips this whole delegation for a trivial run — under
  `trivialDiffThreshold` changed lines (default 10) and every changed path
  matching `trivialDiffPaths` (default `*.md`, `*.css`, `*.svg`,
  `public/**`), both configured in `.claude/harness.json`.
- **Gate 6 — harness-review**, on the run's last group with pending tasks,
  before its commit — but only when a 0-token precondition check finds this
  run actually touched something it could review (`CLAUDE.md`/`AGENTS.md`,
  `.claude/`, `.husky/`, `openspec/config.yaml`, or a `package.json`
  script/dependency change);
  skipped otherwise, since most runs never touch the harness. When it runs,
  it shows every finding with a suggested fix regardless of verdict —
  nothing is silently auto-applied.

## Definition of Done

Three layers, in this order. "Done" means all three are green for the
change as a whole — not any one of them in isolation:

1. **Static** — `.husky/pre-commit` (typecheck + lint + lint-staged). Runs on
   every commit.
2. **Runtime** — `.husky/pre-push` (the coverage-mode test run). Runs on
   every push.
3. **System** — Gate 3 (`web-qa`), a real-browser pass over the change's
   whole diff, run once on the last task group before Gate 4.

**No refactor before green.** Don't clean up, simplify, or restructure code
in a change until all three layers pass for that change as a whole — a
tidier version of code that isn't yet Static/Runtime/System-green isn't
progress, it's a second unfinished thing stacked on the first. This is also
why Gate 4 downgrades simplification/refactor findings to PLAUSIBLE on a
run that isn't the change's final one (see `agents/code-reviewer.md`'s
Verification bar) — the System layer hasn't covered the change as a whole
yet on a non-final run, so refactoring ahead of it is premature by this same
rule.

Package manager: {{PACKAGE_MANAGER}}. Framework: {{FRAMEWORK}}. Test runner:
{{TEST_RUNNER}}. (Filled in by `init-harness` — do not leave as literal
placeholders in the generated file.)
