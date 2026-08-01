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

Run both automated scripts **first**, every time — they're free, need no
network, and between them they cover the manifest shapes, the frontmatter,
and every hook's actual decision. Don't start the manual passes below if
either fails.

```
bash tests/smoke-json-schema.sh   # manifests, frontmatter, official validator
bash tests/hook-behaviour.sh      # every hook's decision, on a throwaway repo
```

`smoke-json-schema.sh` would have caught #1 and #21 by itself, and now also
runs `claude plugin validate --strict` when the CLI is available — that is
the check that caught all five agents loading with empty frontmatter.
`hook-behaviour.sh` builds a real git repo from the vite fixture and asserts
on what each hook returns, which is what caught the `npx tsc` fallback
running a stub package instead of the compiler.

---

## 0. Setup (once per fixture, per pass)

The plugin must be tested against a repo it doesn't already live inside.

1. Copy `tests/fixtures/vite-vitest-yarn/` (or `next-jest-pnpm/`) to a
   scratch directory outside this repo.
2. `cd` into the copy: `git init && git add -A && git commit -m "init fixture"`.
3. Install/enable this plugin. From any directory outside the plugin repo:

   ```
   claude plugin marketplace add /abs/path/to/sdd-harness-web-ykryshtopa
   claude plugin install sdd-harness-web-ykryshtopa@sdd-harness-web-ykryshtopa
   claude plugin details sdd-harness-web-ykryshtopa
   ```

   `details` is the fast sanity check: it must list 9 skills, 5 agents by
   name, 3 hook events and 1 MCP server. Agents showing up unnamed or
   missing means their frontmatter failed to parse. Undo afterwards with
   `claude plugin uninstall` + `claude plugin marketplace remove`.
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
4. `openspec config list` shows `new`/`continue`/`verify` present in the
   workflow list, and `.claude/harness.json`'s `openspec.workflows` records
   the list that command actually printed — not an idealised full set.
5. **Negative test A**: run `openspec config reset`, then re-run
   `init-harness`. It must stop with a clear message about the missing
   workflows — not silently continue.
6. **Negative test B** (the likelier one): leave `profile: custom` but
   deselect `new` and `verify` in `openspec config profile`. `init-harness`
   must still stop — a custom profile with an incomplete selection is not
   good enough, and keying the check on the profile string instead of the
   workflow list is exactly how this passes when it shouldn't.
7. `.claude/docs/git-conventions.md` and `review-gates.md` exist, with the
   coverage threshold and package-manager commands actually filled in (no
   literal `{{PLACEHOLDER}}` text left over).
8. `CLAUDE.md` (or `AGENTS.md`) has a pointer block to `.claude/docs/*` and
   `.claude/harness.json`. Re-run on a repo that already had a CLAUDE.md —
   original content must survive, the block only appended.
9. `.husky/pre-commit` runs typecheck + lint + `lint-staged` only (no full
   coverage run); `.husky/pre-push` runs the full coverage script. Both
   executable.
10. `.claude/settings.json`'s `permissions.allow`/`deny` contains the merged
    template entries (see `02-p1-security` checks below) — merged into an
    existing block if one was already there, not overwritten.
11. `.claudeignore` exists; re-running `init-harness` a second time changes
    nothing (idempotency — no duplicated lines, no clobbered hand-edits).
12. `hooks/hooks.json` was **not** copied into the fixture's own
    `.claude/settings.json` — the plugin's hooks apply once, from the
    plugin itself. Check for double-firing: make one commit through Claude
    and confirm the commit guard fired once, not twice (it's a plain shell
    hook now, not an agent delegation — a second copy would show up as a
    duplicated confirmation prompt).
13. Open a session **from a subdirectory** of the fixture (e.g. `src/`) and
    `Read` a `.claudeignore`-covered path such as `coverage/index.html` —
    it must still be denied. Both project-file hooks resolve paths against
    `${CLAUDE_PROJECT_DIR}`; before that fix, a subdirectory session
    silently disabled `.claudeignore` enforcement and the typecheck hook
    alike.
14. Introduce a type error the model can't resolve (e.g. reference a type
    from a package that isn't installed), then end a turn. The typecheck
    Stop hook must block **once**, hand the error text back, and then let
    the turn end — not re-run the full typecheck on every following stop
    until Claude Code's 8-block cap force-ends it. Confirm the second stop
    is fast (the hook exits on `stop_hook_active` before running `tsc`).

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
   the real dev server — not just reading code. Check this by name, not by
   vibe: the subagent's tool calls must be
   `mcp__plugin_sdd-harness-web-ykryshtopa_playwright__browser_*` (the
   plugin-scoped form). A report that reads plausible but contains no
   `browser_*` call at all is the failure mode this check exists for — the
   agent launches fine with only `Read`/`Grep`/`Glob` and will happily
   describe the UI from source.
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

## 6-7. Gate 4 + Gate 5 — code-review (merged, one delegation, #33)

Both gates are now one delegation to the `code-reviewer` subagent, returning
a two-section report — the checks below still verify each gate's own
behavior independently, just within that single spawn.

Gate 4 section:

1. Run it against a diff with one planted, unambiguous bug (e.g. an
   off-by-one) — confirm CONFIRMED, with file/line and the concrete
   failure mode.
2. Run it against a diff with only a debatable style/simplification point
   — confirm PLAUSIBLE, and confirm PLAUSIBLE-only never blocks the commit.
3. Confirm the model used matches `.claude/harness.json`'s `models.code`
   key, not whatever the agent's own frontmatter default is (override the
   manifest value and confirm the override actually takes effect). There is
   no separate `models.testCoverage` key any more — the Gate 5 section runs
   on this same model.
4. Confirm `--fix` applies a finding only after explicit confirmation, not
   automatically.

Gate 5 section:

5. Add source code with **no** accompanying test changes in the same group
   — confirm the section fires (source-only should trigger it, not just
   tests-only — this is #10's fix).
6. Add only test changes with no source changes — confirm it also fires.
7. Add neither (e.g. a comment-only or doc-only diff) — confirm the report
   states the Gate 5 section is not applicable, and confirm the agent still
   ran (Gate 4 doesn't skip) rather than the whole delegation being skipped.
8. Drop coverage below the fixture's configured `coverageThreshold` on
   purpose — confirm the report states the gap against that exact number,
   not a hardcoded default.
9. Confirm one CONFIRMED finding in *either* section pauses before push —
   test this separately for a Gate-4-only CONFIRMED and a Gate-5-only
   CONFIRMED, since a bug that only pauses on one section but not the other
   would silently reduce the merged gate's coverage relative to the two
   separate gates it replaced.

Review-depth-by-classification (#34):

10. Run an autonomous batch of 3+ `isolated` groups — confirm `code-review`
    spawns exactly **once** for the whole batch, against the cumulative
    diff of all groups' commits (`git diff <parent>..HEAD`), not once per
    group. Each group should still get its own commit (check `git log
    --oneline` on the batch branch — one commit per group), just without a
    per-group review spawn.
11. Run a single `judgement-heavy` group — confirm `code-review` still
    spawns once, against that one group's diff (a judgement-heavy run is
    already "a batch of one," so this should look identical to before #34).
12. Plant a CONFIRMED finding in a *non-last* group of an isolated batch —
    confirm it only surfaces after the whole batch is committed (at the
    batch-level `code-review` pass), and confirm its fix lands as a new
    commit appended to the batch branch, not an amend of that earlier
    group's own commit.

Trivial-diff pre-filter (#36):

13. Make a run whose entire cumulative diff is a 3-line `.md` edit — confirm
    `code-review` never spawns at all, and `.claude/harness-log.jsonl` gets
    both the `code-review` and `test-coverage` lines written directly by
    `opsx-apply-git` with `"verdict":"skipped"`.
14. Make a run that's still `.md`-only but exceeds `trivialDiffThreshold`
    (default 10) changed lines — confirm the pre-filter does NOT skip it
    (line-count check, not just path check).
15. Make a run that's under the line threshold but touches one `.ts`/`.tsx`
    file alongside `.md` files — confirm the pre-filter does NOT skip it
    (a single non-trivial path disqualifies the whole run).
16. Edit `.claude/harness.json`'s `trivialDiffThreshold` down to `0` —
    confirm even a 1-line `.md` diff now runs the full `code-review`
    delegation, proving the threshold is actually read from the manifest
    and not hardcoded.

## 8. Gate 6 — harness-review

1. Edit `.claude/docs/review-gates.md` by hand to say something false
   about a gate's trigger, then run this gate on the last group of an
   unrelated change — confirm it flags the drift (this run touches
   `.claude/`, so the precondition in #4 below should let it run at all).
2. Re-run the Gate-1-negative-test scenario (`openspec config reset`) and
   confirm this gate also independently notices the profile regression,
   not only `init-harness`'s own check.
3. Confirm every finding is shown with a suggested fix regardless of
   verdict, and nothing is auto-applied without the human choosing to.

Precondition (#35):

4. Run a change whose diff touches only application source/test files —
   nothing under `CLAUDE.md`/`AGENTS.md`/`.claude/`/`.husky/`, no
   `openspec/config.yaml` edit, no `package.json` script/dependency change —
   confirm `harness-reviewer`
   never spawns for it, and `.claude/harness-log.jsonl` gets a
   `"gate":"harness-review","verdict":"skipped"` line written directly by
   `opsx-apply-git` (not by the harness-review skill, which never ran).
5. Run a change that only adds a `package.json` script (no `.claude/`/
   `.husky/`/`CLAUDE.md` touched) — confirm the precondition still fires
   and `harness-reviewer` runs, since a script/dependency change is the
   other half of the precondition, not just harness-path changes.
6. Run a change that only edits `openspec/config.yaml`'s `context:` block —
   confirm the precondition fires for that too, and that the review compares
   the edited context against `.claude/harness.json` rather than accepting
   it. This is the path most likely to go stale unnoticed, since nothing
   breaks when it's wrong.

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
