# Manual regression checklist

This plugin has no CI and no automated way to drive Claude Code itself, so
the 6 review gates, the hook layer, and `init-harness` can only be verified
by actually installing the plugin into a real repository and running it.
That gap is exactly how three silent P0 bugs (#1 the missing `"hooks"`
wrapper, #2 the missing `Edit` tool on `spec-reviewer`, #3 the
nonexistent `openspec` npm package) reached commit `e57b8ad` unnoticed —
all three are quiet failures with no error message a human would stumble
onto without a real run.

Run this checklist:
- before merging `bugfix/harness-improve` into `main`,
- after any change that touches `hooks/hooks.json`, an `agents/*.md`
  frontmatter block, `skills/init-harness/**`, or the manifest schema.

Use both fixtures in `tests/fixtures/` — they deliberately differ on every
axis the harness claims to generalize across (framework, package manager,
test runner). A fix that only gets tried against one of them is unverified
on the other.

Run `tests/smoke-json-schema.sh` **first**, every time — it's free, and it
would have caught #1 and #21 by itself. Don't start the manual passes below
if it fails.

```
bash tests/smoke-json-schema.sh
```

---

## 0. Setup (once per fixture, per pass)

The plugin must be tested against a repo it doesn't already live inside.

1. Copy `tests/fixtures/vite-vitest-yarn/` (or `next-jest-pnpm/`) to a
   scratch directory outside this repo.
2. `cd` into the copy: `git init && git add -A && git commit -m "init fixture"`.
3. Install/enable this plugin in that repo (local marketplace path, or
   however dev builds are normally installed).
4. Install real dependencies: `yarn install` (vite fixture) or
   `pnpm install` (next fixture) — needs real registry access.
5. Confirm the plugin's own hooks fire at all: open a session in the
   fixture repo and check the `SessionStart` banner prints branch/status/
   recent commits. If it doesn't print anything, stop — the hook layer
   isn't loading and nothing below this line is meaningful yet (this is
   exactly what #1 broke).

Record for this pass: fixture name, plugin commit/branch under test, date.

---

## 1. `init-harness` and the stack manifest

1. Run `/init-harness` (or the plugin's namespaced form) in the fixture repo.
2. Detection matches the fixture's own README table exactly:
   framework, package manager, test runner, build dir, dev server URL.
3. `.claude/harness.json` exists and its `scripts.*` keys point at real
   `package.json` script names (never invented ones).
4. `openspec config list` shows `profile: custom` with `new`/`continue`/
   `verify` present in the workflow list (Expanded, not Core).
5. **Negative test**: run `openspec config reset`, then re-run
   `init-harness`. It must stop with a clear message about the profile
   being back on Core — not silently continue.
6. `.claude/docs/git-conventions.md` and `review-gates.md` exist, with the
   coverage threshold and package-manager commands actually filled in (no
   literal `{{PLACEHOLDER}}` text left over).
7. `CLAUDE.md` (or `AGENTS.md`) has a pointer block to `.claude/docs/*` and
   `.claude/harness.json`. Re-run on a repo that already had a CLAUDE.md —
   original content must survive, the block only appended.
8. `.husky/pre-commit` runs typecheck + lint + `lint-staged` only (no full
   coverage run); `.husky/pre-push` runs the full coverage script. Both
   executable.
9. `.claude/settings.json`'s `permissions.allow`/`deny` contains the merged
   template entries (see `02-p1-security` checks below) — merged into an
   existing block if one was already there, not overwritten.
10. `.claudeignore` exists; re-running `init-harness` a second time changes
    nothing (idempotency — no duplicated lines, no clobbered hand-edits).
11. `hooks/hooks.json` was **not** copied into the fixture's own
    `.claude/settings.json` — the plugin's hooks apply once, from the
    plugin itself. Check for double-firing: make one commit through Claude
    and confirm the commit-gate agent hook and typecheck hook each ran
    once, not twice.

---

## 2. Security / permissions (independent of stack)

1. `Read` a `.env` file directly (Read tool) — denied.
2. `Bash(cat .env)` — denied. `Bash(node -e "...")` reading `.env` — the
   allow-list should no longer grant this at all; the attempt should need
   confirmation or fail outright, not sail through.
3. `Read .gitignore` and `Read .github/workflows/*.yml` (or equivalent
   ordinary repo files) — these must work; the deny-list should not be so
   broad it blocks normal repo reading.
4. On a feature branch, `git push --force` — hook asks for confirmation.
5. `git merge`/`git push` while checked out on the repo's actual default
   branch (whatever `origin/HEAD` resolves to, not assumed to be `main`) —
   asks for confirmation.
6. Detached HEAD: `git checkout <sha>`, then attempt `git push` — hook asks
   for confirmation rather than silently allowing (it can't verify branch
   name in this state).
7. `.claudeignore`-covered path — `Read`/`Grep`/`Glob` all denied for it,
   not just `Read`.

---

## 3. Gate 1 — architecture-review

1. Draft an OpenSpec `design.md` for a toy feature that deliberately mixes
   a UI component with direct persistence/service logic.
2. Trigger the gate right after `design.md` is done, before specs/tasks are
   drafted (Expanded profile makes this insertion point exist at all —
   this is what #44 fixes).
3. Confirm it reports the boundary violation as CONFIRMED with a concrete
   fix, not vague style commentary.
4. Confirm a clean `design.md` produces no pause.

## 4. Gate 2 — spec-review

1. Run it on the full artifact set (proposal, design, specs, tasks) for the
   toy feature above.
2. Confirm every group in `tasks.md` gets labeled `isolated` or
   `judgement-heavy` — inspect the file directly, don't take a verbal
   summary's word for it (this is what #2's missing `Edit` tool silently
   broke: the label never landed in the file).
3. Introduce a requirement with no corresponding task, and one untestable
   requirement — confirm both get flagged.

## 5. Gate 3 — web-qa

1. Implement one small user-facing flow (the fixture's own counter/home
   page is enough) and run the gate on the last task group.
2. Confirm it actually drives a real browser via Playwright MCP against
   the real dev server — not just reading code.
3. Occupy the fixture's default dev server port (`5173`/`3000`) with
   another process first — confirm the gate reads the *actual* port Vite/
   Next fell back to (`5174`/`3001`) from the dev-server process's own
   stdout, rather than assuming the default.
4. Confirm the dev server it started is torn down after the gate, even on
   a FAIL path.
5. Introduce one genuine UI bug — confirm the gate reports FAIL with the
   specific broken flow, blocking (must-pass, not advisory).
6. Confirm a change with no user-facing surface (e.g. a pure utility
   function) correctly skips this gate instead of running it pointlessly.

## 6. Gate 4 — code-review

1. Run it against a diff with one planted, unambiguous bug (e.g. an
   off-by-one) — confirm CONFIRMED, with file/line and the concrete
   failure mode.
2. Run it against a diff with only a debatable style/simplification point
   — confirm PLAUSIBLE, and confirm PLAUSIBLE-only never blocks the commit.
3. Confirm the model used matches `.claude/harness.json`'s `models.code`
   key, not whatever the agent's own frontmatter default is (override the
   manifest value and confirm the override actually takes effect).
4. Confirm `--fix` applies a finding only after explicit confirmation, not
   automatically.

## 7. Gate 5 — test-coverage

1. Add source code with **no** accompanying test changes in the same group
   — confirm the gate fires (source-only should trigger it, not just
   tests-only — this is #10's fix).
2. Add only test changes with no source changes — confirm it also fires.
3. Add neither (e.g. a comment-only or doc-only diff) — confirm it's
   skipped.
4. Drop coverage below the fixture's configured `coverageThreshold` on
   purpose — confirm the gate reports the gap against that exact number,
   not a hardcoded default.

## 8. Gate 6 — harness-review

1. Edit `.claude/docs/review-gates.md` by hand to say something false
   about a gate's trigger, then run this gate on the last group of an
   unrelated change — confirm it flags the drift.
2. Re-run the Gate-1-negative-test scenario (`openspec config reset`) and
   confirm this gate also independently notices the profile regression,
   not only `init-harness`'s own check.
3. Confirm every finding is shown with a suggested fix regardless of
   verdict, and nothing is auto-applied without the human choosing to.

---

## 9. Workflow resilience (`opsx-apply-git`)

1. Merge a run's PR via **squash merge** on the remote, then run the next
   `opsx-apply-git` continuation — confirm it recovers (recognizes the
   squashed commit as merged) instead of failing to find matching commits.
2. Confirm a change's archive PR is only opened *after* its own run's PR
   has actually merged, never before or in parallel.
3. Repeat the default-branch and detached-HEAD checks from section 2
   specifically through `opsx-apply-git`'s own git operations, not just the
   raw hook.

---

## Sign-off

| Fixture            | §0 setup | §1 manifest | §2 security | Gate 1 | Gate 2 | Gate 3 | Gate 4 | Gate 5 | Gate 6 | §9 workflow | Date | Notes |
|--------------------|----------|-------------|--------------|--------|--------|--------|--------|--------|--------|-------------|------|-------|
| vite-vitest-yarn   |          |             |              |        |        |        |        |        |        |             |      |       |
| next-jest-pnpm     |          |             |              |        |        |        |        |        |        |             |      |       |

Fill in PASS/FAIL per cell. A FAIL blocks merging whatever change triggered
this run of the checklist — file it as a new finding rather than waving it
through.
