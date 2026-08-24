# Automated Review Gates

AI review is a sensor, not a final verdict — the human owns the merge.
Gates 1, 2, 2b, 4, 5 surface findings and pause only on a CONFIRMED finding;
PLAUSIBLE-only or clean reviews never pause anything. Gates 3 and 6 differ
by design (see below).

- **Gate 1 — architecture-review**, after `design.md` is drafted.
- **Gate 2 — spec-review**, after the full artifact set is done. Also
  classifies every `tasks.md` group isolated/judgement-heavy.
- **Gate 2b — scaffold-review**, inside `opsx-scaffold`, on a change whose
  proposal step judged it needs a scaffold (`.scaffold` marker `yes`) and
  whose manifest has `scaffold.enabled: true`. `architecture-reviewer`, in
  its scaffold-review mode, checks the scaffold's file layout, signatures,
  and imports against `design.md`'s already-approved boundaries — never the
  architecture itself, which stays Gate 1's job. A change whose marker is
  `no` never invokes `opsx-scaffold` at all; a repo without the manifest key
  (or `enabled: false`) still invokes it, but it stops at its own key check
  before reaching this gate. Either way, no scaffold-review line is logged.
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
- **Deep review**, inside the same `code-review` step and logged under its
  own `deep-review` name: a security and architecture-as-built pass on top
  of Gates 4/5, spawned only when a second 0-token prefilter finds a risk
  signal in the diff (auth, permissions, payments, migrations, config,
  secrets, uploads). Most runs skip it, and the skip is logged too. It is
  not a seventh gate — it pauses on a CONFIRMED finding exactly like Gate 4.
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
2. **Runtime** — `.husky/pre-push` (the coverage-mode test run, then a
   dependency-vulnerability audit — `{{PACKAGE_MANAGER}} audit` or its
   equivalent, blocking on a high-or-above severity finding). Runs on every
   push. The audit is blocking, not informational: an install command can't
   add a vulnerable package in the first place (`permissions.deny` blocks
   every package manager's install commands), so this is the check for what
   was already in the lockfile, including transitively.
3. **System** — Gate 3 (`web-qa`), a real-browser pass over the change's
   whole diff, run once on the last task group before Gate 4 *if the change
   touched user-facing UI*; not applicable to a change that didn't (e.g.
   backend/API-only), in which case Static and Runtime are the whole
   contract for that change. Like the first two layers, it now leaves files
   behind: a passed flow the human agreed to keep is saved as a
   `@playwright/test` scenario under `webQaScenariosDir`, and every later
   Gate 3 run replays the accumulated set before its own click pass.

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

## Harness diet

**Step 0, before the month starts.** A model downgrade is checked against a
fixed set of cases with known right answers *before* it is trusted with a
month of real work. The plugin's maintainer keeps such a set (`evals/` in
the plugin repo) and measures both models on it in one sitting; if the
cheaper model loses a case the current one passes, the trial never starts
and the reason is a named case, not an impression. A repo that has no such
set of its own skips this step and says so in the decision record below —
"not measured against a reference set" is a fact worth recording, because
the rest of this ritual cannot supply it.

Then, once a month: temporarily skip one gate's delegation (no config flag
for this — just don't invoke it for the trial window) or downgrade one
gate's model via `.claude/harness.json`'s `models.*`, run the normal flow of
changes for that stretch,
then compare the `harness-review` skill's stats summary (the
`${CLAUDE_PLUGIN_ROOT}/skills/harness-review/references/harness-stats.md`
procedure, reading this repo's own
`.claude/harness-log.jsonl`) from before and after. If nothing measurable
changed — verdict distribution, escalation count, `reviewConfidence: low`
share, `tokensTotal` sum/median (a cheaper-per-step model can still cost
more if it needs several times the steps; `durationMs` alone won't show
that) — that gate or model was probably doing less than its cost implied;
consider trimming
it for good. If something did change, put it back and record what you
tried and what you found as a new file in `docs/decisions/`. That record
carries **both** numbers: accuracy against the reference set from step 0,
and cost/verdict distribution from the log. A record with only the second is
the one this ritual is most likely to get wrong — the production stream has
no fixed reference, so a model that started missing defects and a month that
simply had fewer of them read exactly alike. This is the
same ratchet principle this harness applies to what gets *added* — it's
also supposed to apply to what's already here.

Same cadence, separate ritual: run the `dead-code-report` skill about once a
month too. None of the six gates above ever looks at code a task stopped
referencing without touching it, so that only accumulates unless something
goes looking on a schedule. It only reports and drafts a change proposal —
it never deletes anything itself.
