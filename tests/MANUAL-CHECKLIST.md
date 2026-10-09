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
- before merging a release's integration branch into `main`,
- after any change that touches `hooks/hooks.json` or `hooks/git-guard.sh`, an `agents/*.md`
  frontmatter block, `skills/init-harness/**`, or the manifest schema.

Use both fixtures in `tests/fixtures/` — they deliberately differ on every
axis the harness claims to generalize across (framework, package manager,
test runner). A fix that only gets tried against one of them is unverified
on the other. **Run the whole checklist to completion on both fixtures
before merging into `main`** — 0.2.0's live passes only ever ran against
`vite-vitest-yarn`; `next-jest-pnpm` never got a full live run before that
release shipped. Don't repeat that gap for 0.3.0.

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

   `details` is the fast sanity check: it must list 10 skills, 5 agents by
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

## 1a. Upgrading from 0.2.0 (`init-harness` upgrade mode) (#U1, #U18)

This is the release's one breaking change (see README's "Upgrading from
0.2.0" section) and the scenario 0.2.0 itself never got a real fixture for —
verify it end to end, on a repo genuinely configured by the *old* plugin,
not one that merely lacks a `harnessVersion` key by coincidence.

1. Get a real 0.2.0 checkout of the plugin: `git worktree add
   /tmp/plugin-0.2.0 f416d53` (the commit `harness-audit/v0.3.0-implemented/00-README.txt`
   itself names as this release's base — the tip of `bugfix/harness-improve`
   before any 0.3.0 work landed; use the
   `sdd-harness-web-ykryshtopa--v0.2.0` tag instead if one has been pushed by
   the time you run this).
2. In a **fresh** copy of a fixture, `claude plugin marketplace add
   /tmp/plugin-0.2.0` and install from it, then run `/init-harness`
   (first-time path). Confirm `.claude/harness.json` has **no**
   `harnessVersion` key afterward — that's what makes this a genuine
   "pre-#U1" repo, not just an unlucky one.
3. Hand-edit `.claude/docs/git-conventions.md`: append one custom paragraph
   that isn't in the template. This simulates a real user's customization
   that upgrade mode must not clobber.
4. Point the marketplace at the current checkout instead (whatever branch or
   worktree holds the plugin version under test — `git branch --show-current`
   if unsure) and reinstall — this is the manual stand-in for
   `/plugin update`, which only refreshes the plugin half, never the
   repository.
5. Run `/init-harness` again in the **same** fixture repo (not a new one).
   Step 0 must select branch 3 (UPGRADE MODE) — confirm the skill says so
   explicitly, naming the version transition, rather than silently
   re-running the full first-time questionnaire.
6. Confirm the new files/keys actually appear, per the inventory table in
   `skills/init-harness/SKILL.md`'s Step 0:
   - `PROGRESS.md` created at the repo root (fresh, no current change);
   - `.claude/docs/laziness-ladder.md` created;
   - `openspec/config.yaml` gains its `context`/`rules` keys without its
     `schema` key or any other existing content being touched;
   - `.gitattributes` gains no `merge=union` line (0.12.0); on a project set
     up before 0.12.0, its `PROGRESS.md merge=union` and
     `.claude/harness-log.jsonl merge=union` lines are removed, every other
     line stays, and `.claude/harness-log.jsonl` itself is kept;
   - `PROGRESS.md` is in `.gitignore`; on a project set up before 0.12.0,
     `git status` shows it deleted from the index while the file is still
     on disk (`git rm --cached`);
   - `.playwright-mcp/` is in `.gitignore`, on a fresh install and after an
     upgrade; a second run adds no duplicate line;
   - on a 0.11.0 project, `.husky/pre-push`'s log-only check is offered as
     a one-line diff to the per-branch pattern;
   - `.claude/harness.json` gains `harnessVersion`, `maxFixAttempts`, and
     `toolchainVerifiedAt`.
7. Confirm the hand-edited paragraph from step 3 survived — `init-harness`
   must show the diff and ask before touching a file that already differs
   from the template, never overwrite it silently. Decline the overwrite and
   confirm the custom paragraph is still there afterward.
8. Confirm `.claude/harness.json`'s `harnessVersion` now equals this
   checkout's `plugin.json` version, and that Step 10's report states the
   transition as `<old or "unversioned"> -> <new>`, plus a per-file list of
   created/appended/left-alone — not just "done."
9. Run `/init-harness` a **third** time. Step 0 must select branch 2
   (`harnessVersion` already equals `plugin_version`) — confirm it says so
   and stops, touching nothing, rather than re-running the upgrade walk.

## 1b. Blocking dependency audit on `pre-push` (#U12)

1. On a fixture already configured by the current `init-harness`, read
   `.husky/pre-push` directly — confirm it opens with the log-only block
   (0.11.0) and then chains `<pm> test:coverage && <audit
   command>`, with the audit command's spelling matching this fixture's
   package manager (and, for yarn, its major version — `yarn audit --level
   high` for 1.x, `yarn npm audit --severity high` for 2.x+).
2. Add a devDependency at a version with a known high-or-above severity
   advisory, install it, and attempt `git push`. Confirm the push is
   blocked (non-zero exit) and the audit's own output — naming the
   vulnerable package — reaches the terminal, not swallowed by the chain.
3. Upgrade or remove that dependency and push again — confirm it now
   succeeds (assuming coverage also passes).
4. Confirm `.husky/pre-push` does **not** also run `<pm> outdated` — Step
   3 item 4 of `init-harness` explicitly rules this out, since a
   version-drift check left in the same chain would leave the hook
   permanently red on any stale minor version and train people to ignore it.

### Local stack fields (0.11.0)

5. A project with a local stack, `tests.integration` holding `requires`
   and `healthCheck` but **no** `envCommand`: `init-harness` writes no
   `tests/integration/global-setup.ts`; with no `mailCatcherUrl` either,
   `web-qa` offers no email-flow template and `web-qa-manual-tester` asks
   the human for an email's link.
6. Set `healthCheck` to a command containing a single quote (e.g.
   `docker compose ps --filter name='^db$' -q`), accept the integration
   layer, and run `npx tsc --noEmit` on the written global setup — it
   compiles.
7. Point `envCommand` at a stub printing `{"API_URL":"https://example.com"}`
   and run the integration script — it stops with one line naming
   `API_URL` and the host, before any test. With the real `envCommand` and
   the stack up, an integration test that imports app code through `@/…`
   passes: the written config resolves the alias the way the main test
   config does.

### Integration tests in `pre-push` (0.11.0)

The template itself is run by `tests/hook-behaviour.sh`; these check it on
a real project with a local stack:

8. Stop the stack, `git push`: one line, "pre-push: local services are not
   running — start them with: <requires>", and the push is refused.
9. Start the stack, push again: the integration tests run against it and
   the push goes through.
10. With the stack up, put a wrong service address into `.env.local` for a
    moment: the integration tests still pass — they never read `.env*`.
    Catching that address is the environment check's job
    (`tests.e2e.preflight`), not `pre-push`'s. Put the address back.
11. After `init-harness`, `.gitignore` holds `.claude/.last-pre-push.json`,
    and `git status` stays clean after a push.
12. An `opsx-apply-git` run: the log has a `gate:"integration"` line, and
    the push of the log commit at §4 step 6.2 prints "only the harness log
    changed — tests skipped" and takes about a second.
13. Upgrade mode on a project whose `pre-push` is the plain 0.10.6 chain:
    a diff to the new hook, applied on yes. On a hand-edited `pre-push`:
    both blocks printed for a manual merge, the file left alone.
14. `init-harness` with the stack stopped: the report says the integration
    tests weren't verified, `tests.integration` stays in the manifest, and
    `.husky/pre-push` still has its integration block — the first push
    stops with step 8's one line.
15. Delete the integration block from `.husky/pre-push` by hand and run
    `opsx-apply-git`: after its push, one line says the hook doesn't run
    the integration tests, and the log line is `no fresh hook result`. A
    group that writes an integration test with the stack stopped says the
    same at the end of its "not verified" line.

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
7. No `tests.e2e.preflight` in the manifest: the report has one line, "no
   environment check — …", and everything else runs as before.
8. `tests.e2e.preflight` naming a script that exits 1: the report opens
   with `Environment: …`; no replay, no manual pass, no `debug-loop`; the
   dev server is gone; the log has a `confirmed` verdict line and a
   `web-qa-flows` line with `failureKind: "environment"`.
9. The same script exiting 0: the gate goes on, and the delegation prompt
   to `web-qa-manual-tester` says "environment check passed".
10. A flow whose page loads a font or an analytics script from another
    host: the recording question names the host and offers `@external`,
    untagged, or not recorded. "Untagged" writes the scenario without
    `@external`, and the replay before push runs it.
11. A change with a sign-in and a page that sends an expired login back to
    `/sign-in`: the agent finds the login cookie with `browser_cookie_list`,
    deletes it with `browser_cookie_delete`, reloads, and judges the
    redirect itself — no help from the calling session. That flow's row
    names both calls. The Keyboard Pass row for tab order lists the
    recorded order (`Email → Password → Sign in`), not just PASS.
12. With `"webQa": "haiku"`: a change reaching two screens runs the agent
    on haiku; one reaching five says `5 flows → sonnet` and runs on
    sonnet. The log line's `model` names what actually ran. With
    `"webQa": "opus"`, five flows still run on opus.

## 5a. `debug-loop` — bounded fix loop and escalation (#U6, #U18)

`debug-loop` is not a gate — it never appears in `review-gates.md` and never
blocks on its own. It's the thing a gate calls into when it has a concrete
failure to fix, and the whole point of 0.3.0's #U6 is that it stops instead
of looping forever.

1. Set `.claude/harness.json`'s `maxFixAttempts` to `2` for a controlled
   run.
2. Introduce a genuine UI bug the gate will FAIL on, but shape it so a
   plausible fix attempt still doesn't resolve it (e.g. the visible bug is a
   symptom of a root cause one directory away from where a naive fix would
   look) — run Gate 3 on it. Confirm `debug-loop` runs exactly 2 attempts,
   each visibly structured as its four phases (reproduce, isolate, diagnose,
   fix-and-reverify), and then **escalates to a human** with a clear message
   naming the failure — not a third silent attempt, not a generic timeout.
3. Confirm the line in `.claude/harness-log/<branch>.jsonl` for that run records
   `fixIterations: 2` and `escalatedToHuman: true`.
4. Repeat with a CONFIRMED `code-review` finding whose suggested fix, once
   applied, still fails re-verification — confirm the same cap and
   escalation apply there too, not just to `web-qa` FAILs.
5. Repeat with a bug that a fix genuinely resolves on the **first** attempt
   (`maxFixAttempts` still `2`) — confirm `debug-loop` does not run a second,
   unnecessary attempt: `fixIterations: 1`, `escalatedToHuman: false`.

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
    `code-review` never spawns at all, and the harness log (`.claude/harness-log/<branch>.jsonl`) gets
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

CR-14 — a new flow or service boundary with no test (0.11.0):

17. On the change's last run, a diff adding a sign-in page with no scenario:
    a PLAUSIBLE CR-14 naming the flow in words. The same diff in a project
    with no `tests.e2e` block: nothing, and one "not applicable" line.
18. The same diff on an early run: no flow finding, one line "scenarios are
    recorded on the last group".
19. A flow listed in the change's `web-qa-flows` `declinedFlows` (or
    `recordedFlows`): not flagged. A new flow `web-qa` never offered:
    flagged.
20. With `tests.integration`: a new function in `lib/dal.ts` that calls the
    stack's client, with no `*.integration.test.ts` → PLAUSIBLE naming the
    file and function. CR-14 is never CONFIRMED anywhere.

Integration tests written with the code (0.11.0, `opsx-apply-git`
`references/integration-tests.md`):

21. A group adding a function in `lib/dal.ts` that calls the stack's client
    writes `*.integration.test.ts` for that function — not for the Server
    Action that calls it.
22. A new function that only talks to a hosted CMS gets no integration
    test.
23. Local stack stopped: the test is still written, the report has
    "integration test <file> not verified: start <requires>", and the group
    is not `blocked`.
24. With `makerChecker.enabled`, step 21's file comes from `test-author`,
    and the implementing session writes no test.

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
   never spawns for it, and the harness log (`.claude/harness-log/<branch>.jsonl`) gets a
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
7. Line budget (0.10.6). The count itself is checked by
   `tests/claude-md-budget.sh`; these steps check what the agents do with
   it. In a test project, make `CLAUDE.md` 130 lines: Stack, Commands, a
   long `## Styling` and a long `## Testing` section, and the harness block.
   Run a change that edits `CLAUDE.md`. Gate 6 reports a CONFIRMED size
   finding with both numbers (root 130, effective with `@`-imports), the
   Deletion Test candidates first, which sections stay, which move to which
   `docs/<topic>.md`, `Doc | Read before…` rows with specific triggers, and
   the line count after the split. Nothing is changed until you approve.
8. Cut that `CLAUDE.md` to 90 lines and repeat: no size finding, one line
   with both numbers.
9. Run `/init-harness` (first install and upgrade mode) on a test project
   whose `CLAUDE.md` is 130 lines before the harness block. The final report
   carries both numbers and the same split proposal, and `git diff
   CLAUDE.md` shows only the appended pointer block.

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
4. In a target project, run a task that needs a probe test. Confirm there is
   no "cd with write operation" prompt, no Python/`sed` file edits (Edit and
   Write only), the probe lives in the scratchpad or is gone before the
   commit, and `git push` runs on its own, not piped.
5. Fresh `init-harness`: the pointer block has the two-line Shell bullet and
   no more; `settings.json` has `Bash(npx vitest run:*)` on the vite fixture
   and `Bash(npx jest:*)` on the next fixture, with no literal `{{...}}`
   left. Change a fixture's runner to something else (e.g. `mocha`) and
   confirm no runner line is written.
6. Upgrade mode on a repo set up by 0.10.0: both the Shell bullet and the
   runner line are added once; a second run changes nothing. Put a
   hand-written `## Shell` section ("don't `cd` into the repo") in its
   `CLAUDE.md` first and confirm the bullet is skipped.
7. Make a run log a skip (a `.md`-only diff): the PR body's Review trail and
   the harness log (`.claude/harness-log/<branch>.jsonl`) show the reason in English (`small change`).

Steps 8-13 check `docs/deferred.md` (0.10.5). They are manual: the eval set
under `evals/` covers skill routing and review misses, not a multi-step
`opsx-apply-git` run. Start from a test project with no `docs/deferred.md`
and a change with at least two groups.

8. Make a group stop on one task (an unanswerable question in a
   judgement-heavy group). `docs/deferred.md` is created from
   `skills/opsx-apply-git/references/deferred-log-template.md`'s header,
   with one `## <change-slug>` heading and one entry, State `blocked`,
   Status `open`. The task line keeps its `- [ ]` and its
   `<!-- blocked: … -->` marker unchanged and gains
   `<!-- deferred: docs/deferred.md -->`. The file is in the same commit as
   the marker.
9. Finish a group with nothing blocked or waived, in a project with no
   `docs/deferred.md`: the file is not created. With the file present: the
   group's commit doesn't touch it (`git show --stat`).
10. Remove the marker from step 8, run the group again and tick the task.
    The entry's Status becomes `resolved (<change-slug>, group N)`; the
    entry and the pointer are still there.
11. Waive one check by your own decision in a group ("skip the live check,
    I'll do it on deploy"), let the run finish, and archive the change. The
    `skipped` entry is still `open`, and the line
    ``Archived at `openspec/changes/archive/<date>-<change-slug>/`.`` sits
    under the change's heading, in the `chore: archive` commit.
12. In the run that leaves step 11's entry open, the PR body's Deferred part
    lists it on one line with a working link to the entry's heading, after
    `proposal.md`'s Open Questions.
13. Copy a real project's `docs/deferred.md` into the test project and repeat
    step 8 there. The new entry is appended under a new `## <change-slug>`
    heading at the end; `git diff` shows no other line changed.

Replay of recorded scenarios before push (§4 step 3a, 0.11.0). Which
scenarios the last run picks is checked by `tests/affected-scenarios.sh`;
these are the step's own decisions:

14. A run that changed only `README.md`: the log has `e2e-replay`
    `skipped` `docs only`, and Playwright never ran. The same `README.md`
    run as the last run of a change whose earlier runs changed code: not
    skipped — the affected scenarios run.
15. A run that changed only `globals.css`: the replay is **not** skipped.
16. Break a recorded scenario with a component change: the run reaches
    `debug-loop` and does not push while the scenario is red.
17. After step 16's fix: `code-review` runs a second time, on
    `git diff <HEAD before step 3a>..HEAD` only, before push. A replay
    green the first time → no second `code-review`.
18. A scenario tagged `@external` (or the manifest's `externalTag`) never
    runs; on an ordinary run only `@<change-slug>` scenarios run, a
    scenario tagged `@<change-slug>-v2` does not, and the project's own e2e
    tests outside `tests.e2e.dir` do not.
19. Point `playwright.config`'s `testDir` away from `tests.e2e.dir`: one
    environment line ("testDir … doesn't cover …"), `failureKind`
    `environment`, no `debug-loop`, no push.
20. A manifest with no `tests.e2e` block: `skipped` `e2e not configured`;
    everything else as in 0.10.6.
21. The last group with UI: `web-qa` passed and nothing but `.md` was
    committed after that group's commit → `skipped` `replayed by web-qa`.
    Add a `code-review` fix commit to a source file → the replay runs. A
    `web-qa` that needed a fix along the way (verdict `confirmed`) → the
    replay runs too.
22. Merge a group's PR, stay on its branch and run `opsx-apply-git` again:
    one line says it switched to the PR's base branch, and the run goes on
    with no question. Do the same with the PR still open → it asks which
    branch is the parent. With `forge` `"other"` → it asks, too.
23. Merge the parent into `main`, add a commit to `main`, then run
    `opsx-apply-git` on the parent: it offers to send the PRs into `main`
    and cuts no group before the answer. `PROGRESS.md` gets a `## PR
    target` line; the next run on that parent asks nothing. A parent not
    merged into `main` → no question. A parent squash-merged into `main` →
    no question either (known limit, `parent-branch.md`). Run it once with
    `origin/HEAD` unset (`git remote set-head origin -d`): same result.
    A merged archive branch → it reports the change is archived and stops.
24. Put a package with a known high vulnerability into the parent's
    lockfile, then run a group that changes only source files: the push
    fails, one line says the vulnerability is not related to this run, the
    four-step way out is offered and nothing of it is done, and the log has
    a `gate:"audit"` line with `failureKind` `unrelated`. Change the
    lockfile in the run instead → `failureKind` `app`, no way out offered.
25. `init-harness` on a fresh project: it asks plain audit or the script.
    Script → `scripts/deps-audit.mjs`, `scripts/audit-allowlist.json` (`[]`)
    and the hook calls `node scripts/deps-audit.mjs <pm audit> --json`;
    `depsAudit` is `"script"`. An allowlist entry with a past `expires`
    fails the push again. Upgrade a 0.11.0 project: the question comes once,
    and the hook's audit line is replaced only after the diff is shown.
26. Answer yes to the scheduled audit job: the report prints one weekly job
    that runs the same audit call as the hook and says the project owns
    it; `.github/workflows/` and the rest of the repo have no new file.
27. Upgrade a project whose manifest has `"code": "claude-sonnet-5"` and
    `"webQa": "claude-haiku-4-5"`: afterwards they read `sonnet` and
    `haiku`, and the report lists both changes. Put `"deep": "gpt-5"` in
    instead: the upgrade stops with a message naming `models.deep` and the
    four allowed names, nothing is written and `harnessVersion` stays.
28. A diff that relies on a library header or default (a cache header, a
    cookie flag): the code-review finding about it either cites context7 or
    says `library behaviour not confirmed` with one concrete check, and is
    PLAUSIBLE at most. No report suggests reading `node_modules`. The
    `code-review` and `deep-review` log lines carry `context7Lookups`.
29. Give `harness-review` a project whose `.claude/harness.json` needs a
    fix: every suggested JSON/YAML edit in the report parses (paste it and
    run `jq .`). On a machine with no YAML parser, a YAML suggestion comes
    as words only, marked as not parsed.
30. A judgement-heavy run whose review returns two PLAUSIBLE findings: one
    multi-select question "Fix before push?" lists both. Pick one: it lands
    as its own commit, the other changes nothing, and the log has one
    `fixed` and one `rejected` finding line. An isolated run with the same
    findings asks nothing.
31. Ask for a chore run that bumps one dependency: the branch is
    `chore/<slug>` off the main branch; the log file
    `.claude/harness-log/chore--<slug>.jsonl` has a line per check with
    `change: "<slug>"`; the PR goes into the main branch with "What changed
    and why" and a "Review trail" whose Change line reads `No OpenSpec
    change — chore run <slug>.` and whose base is `main`, not
    `origin/main`. A chore run that edits only a few lines of a `.md` file
    writes `code-review` as `skipped`, `small change`; one that edits
    `.github/workflows/` or `vercel.json` still runs `code-review`. A
    project whose `git-conventions.md` has no chore line gets asked before
    the commit.

## 10. Live project, end to end (0.11.0)

One Next.js project with a local stack, start to finish, by a human:

1. `init-harness` offers the test layers: the integration layer with its
   start command, a Playwright config without `@external`, the environment
   check (a drafted `scripts/qa-preflight.mjs` whose probes name variables,
   never values, and no `Read` of any `.env*` file while drafting), and a
   printed CI template. Declining leaves the repository as it was; no CI
   file is ever written.
2. A change with a UI flow passes `web-qa` and records a scenario.
3. A later change that touches that scenario's page replays it before the
   push of its last run. A later change that doesn't touch the page leaves
   it alone (only the change's own scenarios and the affected ones run).
4. A deliberate break of that page, made in a new change, blocks that
   change's push through `debug-loop`.
5. With the environment check added (step 1), a wrong service address in
   `.env.local` stops the replay before push as an environment failure,
   with no `debug-loop`.

---

## Sign-off

| Fixture            | §0 setup | §1 manifest | §1a upgrade | §1b audit | §2 security | Gate 1 | Gate 2 | Gate 3 | §5a debug-loop | Gate 4 | Gate 5 | Gate 6 | §9 workflow | Date | Notes |
|--------------------|----------|-------------|-------------|-----------|--------------|--------|--------|--------|----------------|--------|--------|--------|-------------|------|-------|
| vite-vitest-yarn   |          |             |             |           |              |        |        |        |                |        |        |        |             |      |       |
| next-jest-pnpm     |          |             |             |           |              |        |        |        |                |        |        |        |             |      |       |

Fill in PASS/FAIL per cell. A FAIL blocks merging whatever change triggered
this run of the checklist — file it as a new finding rather than waving it
through.
