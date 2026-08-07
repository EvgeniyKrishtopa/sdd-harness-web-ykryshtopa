# Changelog

This plugin declares a `version` in `.claude-plugin/plugin.json`, which
means Claude Code pins installs to that string: pushing commits without
bumping it delivers nothing to anyone who already installed. Every release
therefore gets a version bump and an entry here. See "Versioning and
releases" in the README for the procedure.

Versions follow semver. Before 1.0.0, breaking changes land in the minor
position.

## 0.4.1

A correctness fix in `dead-code-report`'s safety net, first automated
coverage for the scripts 0.4.0 added, and a progressive-disclosure pass over
the two largest instructions. Nothing in this release adds a manifest key or
changes a configured repository.

**That does not mean you can skip `/init-harness`.** 0.4.0 and 0.4.1 reach
users as one update, so a repository last configured under 0.3.0 still needs
the upgrade-mode run 0.4.0 describes below, to pick up `webQaScenariosDir`.
Only a repository already at 0.4.0 has nothing to do here.

### Fixed

- **`dead-code-report` could call a referenced file safe to delete.**
  `verify-string-reference.sh` excluded the candidate's own lines by
  filtering whole `grep` output lines on the candidate's path. A line in a
  *different* file that mentions that path — `"dynamicEntry":
  "src/formatPrice.ts"` in a build config, the exact reference the check
  exists to catch — contains the path too, so it was discarded along with
  the self-match and the script reported "nothing found". A file reachable
  only through a config string was therefore promoted into Group 1,
  "reliable / safe to delete". The exclusion now compares `grep`'s path
  field instead of the whole line, and handles a candidate passed as an
  absolute path (which previously failed to match itself at all).

### Added — tests

- `tests/dead-code-scripts.sh`: 10 checks over the five scripts 0.4.0
  added, which shipped with no automated coverage at all. Covers the
  string-reference safety net in both directions, generic-stem
  over-matching, `record-rejection`'s comment preservation / duplicate
  handling / JSONC validity, and `run-knip`'s unavailable-tool path.
- Three structural checks in `tests/smoke-json-schema.sh`: every
  `references/` and `scripts/` file must be reachable from its `SKILL.md`,
  every such path a `SKILL.md` names must exist, and every §-section
  citation (`§4 step 2`, `§5.3`) must resolve to a real section and step.
  An extracted file nobody points at is not documentation kept nearby — it
  is an instruction that silently stopped running, which is the one failure
  mode progressive disclosure introduces.
  The third check exists because the split itself caused that failure:
  moving §5's numbered steps out of `opsx-apply-git` left six citations
  across four files pointing at nothing, one of them inside the block
  written into the user's own `CLAUDE.md`. Those steps are back inline as a
  one-line-each outline — a numbered step other skills cite is a public
  anchor, not detail.

### Changed — instruction size

- `init-harness/SKILL.md` 838 → 408 lines and `opsx-apply-git/SKILL.md`
  475 → 433, by moving conditional and reference-shaped material into
  `references/`. A `SKILL.md` body loads in full every time its skill
  fires; a `references/` file loads only when an instruction says to read
  it. What moved is branch-specific (upgrade mode, the OpenSpec profile
  conversation, archiving, blocked-task handling) or lookup material (the
  manifest schema and field notes, the git-hook procedure, the CLAUDE.md
  block). What stayed inline is every step's existence, its trigger, and
  its stop condition — a run that never opens a reference still knows what
  it must do and when to halt.
- The grandfathered line ceilings in `tests/smoke-json-schema.sh` tightened
  to the new sizes in the same commit, so neither file can grow back into
  the space the split just freed.

## 0.4.0

The six review gates only ever look at what changed in the current task, so
anything that just sits in the project unreferenced was invisible to all of
them. This release gives the harness a way to see the whole project, not
just the diff, and adds the token/skip/outcome fields the journal needed to
answer any question about cost. No breaking change — `init-harness` in
upgrade mode picks up the one new manifest key on its own.

### Added — whole-project blind spots

- `code-reviewer`'s coverage criterion no longer treats a rising coverage
  percentage as reassurance when a diff is deletion-dominated — deleted code
  is by definition uncovered, so coverage always rises on that class of
  change regardless of whether the deletion was safe. The check now asks
  whether the removed code is actually unreferenced instead.
- `dead-code-report` skill: finds unused files, exports, and dependencies
  with `knip` plus the project's own lint rules, sorts findings into three
  confidence groups, and ends with a change-proposal draft — it never
  deletes anything itself. A string-reference safety net downgrades any
  "confident" finding still mentioned as a string anywhere in the project.
  Rejected findings are recorded in `knip.json` with a reason, so repeat
  runs get quieter instead of staying noisy forever. Not a gate; run
  manually, roughly monthly, alongside the existing review-ladder ritual.
- `web-qa` now offers to save each passed browser scenario as a real
  `@playwright/test` file, one at a time, under `.claude/harness.json`'s new
  `webQaScenariosDir`. Later Gate 3 runs replay the accumulated set first,
  at zero model cost, before the manual click pass covers what's actually
  new — closing the gap where a regression in an untouched surface went
  unnoticed until a user hit it.

### Added — plugin size discipline

- A per-`skills/*/SKILL.md` line-count ceiling, checked by
  `tests/smoke-json-schema.sh`. Today's two largest instructions
  (`init-harness`, `opsx-apply-git`) are grandfathered at their current
  length — nothing has to shrink today, but neither may grow further
  unnoticed.

### Added — measurability

- `tokensTotal` — combined token count per gate run, sourced from the
  environment's usage block, added to `.claude/harness-log.jsonl`.
- `skipReason` — closed four-value reason recorded on every skipped gate
  run, instead of a bare "skipped" that couldn't distinguish a healthy
  trivial-diff filter from a gate nobody uses.
- A new `kind: "finding"` log line, written once per CONFIRMED finding when
  `opsx-apply-git` forms a run's summary, recording which gate raised it and
  whether it was fixed, rejected, or deferred — closing the gap where a
  gate's verdict was never checked against what actually happened to it.
- `harness-stats` updated to read all three new fields; `kind: "finding"`
  lines are excluded from the existing per-gate run statistics so they don't
  deflate Gate 6's skipped-percentage denominator.

## 0.3.0

**Repositories `init-harness` already configured under 0.2.0 must run
`/init-harness` again, in upgrade mode, after updating this plugin.**
`/plugin update` only refreshes the plugin itself — its skills, agents, and
hooks; nothing in your repository changes until `/init-harness` runs there
again. This is the one breaking change in this release. See README's
"Upgrading from 0.2.0" for what upgrade mode adds and how it protects your
existing customizations.

### Added — continuity across sessions

- `PROGRESS.md` and `docs/decisions/` ADRs, plus a `SessionStart` digest
  that now prints `PROGRESS.md`'s Status and Next steps, not just
  branch/status/recent commits — a new session's first read now answers
  what `git log -5` alone couldn't.
- `blocked` as a third `tasks.md` task state, alongside done/pending.
- Project-level WIP=1: `opsx-propose-review` refuses to start a new change
  while a previous one sits unarchived, naming it instead of silently
  proceeding.

### Added — bounded debug loop and recovery

- `debug-loop` skill: a bounded, four-phase fix loop (reproduce, isolate,
  diagnose, fix-and-reverify) that escalates to a human at `maxFixAttempts`
  instead of retrying forever — the one place in this harness where cost
  could previously run unbounded. Not a gate; doesn't block on its own.
- A plain-language run summary (3-5 sentences, what changed and why) now
  required in the run's PR body and chat output, not just a commit list.
- Definition of Done named explicitly as an ordered Static -> Runtime ->
  System contract, with "don't refactor before green" as a stated rule.

### Added — review quality

- Laziness ladder (`.claude/docs/laziness-ladder.md`): checked before
  writing new code, referenced from `code-reviewer`'s Simplification
  criterion and from `opsx-apply-git` before implementing a group.
- `code-reviewer` now also judges the observability of the application
  being built (PLAUSIBLE-only) — error handling that swallows context,
  critical paths with no log checkpoint.
- `reviewConfidence: high`/`low` added to all five review agents' Output —
  confidence in the review itself, separate from CONFIRMED/PLAUSIBLE on any
  individual finding; `low` never blocks on its own.
- A blocking dependency-vulnerability audit (`<pm> audit`/equivalent,
  high-or-above severity) chained onto `.husky/pre-push` after the coverage
  run.
- Requirement-ID (`FR-`/`NFR-`) traceability: a 0-token grep check surfaces
  an uncovered identifier by name before `code-reviewer` even runs, and
  reports "traceability unavailable" rather than a false "all covered" when
  a proposal defines no identifiers.
- Gate 6 (`harness-review`)'s CLAUDE.md hygiene check expanded into a
  Deletion Test with a knowledge-routing table.
- Gate 3 (`web-qa`) now requires a UI States Matrix per user-facing
  surface — loading/error/empty/offline, each with a verdict or an explicit
  "not applicable," never a silent skip.

### Added — measurability

- `fixIterations`, `escalatedToHuman`, and `reviewConfidence` fields added
  to every `.claude/harness-log.jsonl` line — all six gates and both of
  `opsx-apply-git`'s skip forms write the identical field set.
- `harness-stats` (`skills/harness-review/references/harness-stats.md`): a
  0-token shell+jq read over the log — verdict/duration distribution,
  fixIterations spread, escalation count, VCR, Rebuild Cost. No model call
  in this path.
- File-handoff: a run's diff over ~50 KB is written to a temp file and
  handed to `code-reviewer` by path instead of inlined as text.
- A monthly "harness diet" ritual, operationalizing this plugin's own
  ratchet principle: temporarily trim one gate or model, compare
  `harness-stats` before/after, keep the trim only on a real difference.

### Fixed — release blockers

- **Upgrade path.** `init-harness` now detects whether a repo was already
  configured by an earlier version (`.claude/harness.json`'s new
  `harnessVersion` key) and switches to upgrade mode: fill in what's
  missing, never silently overwrite a customized file. Gate 6 also checks
  for version drift independently.
- **Toolchain proof.** `init-harness` now actually *runs* the detected
  `typecheck`/`lint`/`test:coverage` scripts and confirms they pass — not
  just that the names exist in `package.json` — before writing
  `toolchainVerifiedAt` and `harnessVersion`. A renamed script now fails
  setup instead of silently shipping a dead `.husky/pre-commit`.
- `init-harness` seeds `openspec/config.yaml` with the project's detected
  context and artifact rules; the file is now in Gate 6's drift-check scope.

### Tests and docs

- `tests/hook-behaviour.sh` and `tests/smoke-json-schema.sh` extended to
  cover every new surface above: `SessionStart`'s three `PROGRESS.md`
  states, the new manifest keys' shape, identical `harness-log.jsonl` field
  sets across all eight write sites, and `debug-loop`'s frontmatter.
- `tests/MANUAL-CHECKLIST.md` gained an upgrade-from-0.2.0 scenario (a real
  0.2.0 checkout, `/plugin update`, `/init-harness` in upgrade mode), a
  `maxFixAttempts`-exhaustion scenario, and a blocking-pre-push-audit
  scenario.
- README brought current with this release end to end: the new "Upgrading
  from 0.2.0" section, a corrected skill count, `init-harness`'s full file
  inventory, the `debug-loop` row, and `reviewConfidence`.

## 0.2.0

The plugin's first working release. 0.1.0 shipped several defects that made
it not do what its own README described; a nine-session audit found and
fixed them. Anyone still on 0.1.0 should update.

### Fixed — gates that silently did nothing

- **Gate 3 ran without a browser.** `web-qa-manual-tester` listed its
  Playwright tools as `mcp__playwright__*`, but a plugin-bundled MCP server
  exposes `mcp__plugin_<plugin>_<server>__<tool>`. No name matched, so the
  agent launched with `Read`/`Grep`/`Glob` only and reported on the source
  instead of the running UI — with no error.
- **Every agent loaded with empty metadata.** An unquoted `description`
  containing `<example>Context: ...` broke the YAML frontmatter, so `name`,
  `description`, `tools` and `model` were all dropped. `tools:` is what
  makes these agents read-only.
- **The hook layer never loaded** (`hooks/hooks.json` was missing its
  top-level `hooks` wrapper), and **`spec-reviewer` had no `Edit` tool**, so
  the isolated/judgement-heavy classification never reached `tasks.md`.
- **OpenSpec was installed from the wrong package** — `openspec` on npm is
  an empty squatter; the real CLI is `@fission-ai/openspec`.

### Fixed — hooks

- The typecheck `Stop` hook ignored `stop_hook_active` and re-blocked every
  stop, up to Claude Code's 8-block cap, on any type error the model
  couldn't fix.
- Its `npx tsc` fallback ran npm's deprecated `tsc` stub package rather than
  the compiler, then reported that stub's output as a type error. The hook
  now resolves the manifest command, then `node_modules/.bin/tsc`, then
  skips.
- Both project-file hooks resolved paths relative to the session's working
  directory, so a session opened in a subdirectory silently disabled
  `.claudeignore` enforcement and the typecheck. They anchor to
  `${CLAUDE_PROJECT_DIR}` now.
- The push guard read `$ARGUMENTS`, which is empty in a command hook, so its
  force-push check never fired. Guards also stopped assuming `main`/`master`
  and now read `origin/HEAD`, and handle detached HEAD.
- The agentic commit gate became a deterministic shell hook: no model call
  per commit.

### Fixed — permissions

- The install-command deny list missed `npm add`, `pnpm install`, `pnpm i`
  and every `bun` spelling, so a block on `yarn add` was routable.
- `Write(path)` rules are accepted by Claude Code but never consulted; the
  template now writes `Edit(path)`, which covers every file-editing tool.
- Dropped an unprompted write grant to `./.claude/skills/**` — a leftover
  from the pre-plugin layout, and a silent channel into files loaded as
  instructions in later sessions.
- Removed `node -e` / `node -p` / `cat` / bare `Write`/`Edit` from the allow
  list, added the git subcommands the workflow actually needs.

### Changed

- Gate 4 and Gate 5 merged into one `code-review` delegation over the same
  diff; review depth follows the isolated/judgement-heavy classification;
  Gate 6 and the whole review pass are skipped for trivial diffs by 0-token
  shell pre-filters. Roughly a 70% cut in agent spawns per change.
- Per-gate model tiers, configured in `.claude/harness.json` rather than
  agent frontmatter.
- `init-harness` writes `.claude/harness.json` as the single stack manifest
  every skill and hook reads, plus a pointer block in `CLAUDE.md`/`AGENTS.md`
  so the harness docs are discoverable at all.
- `init-harness` now gates on OpenSpec's *workflow list* (`new`, `continue`,
  `verify`), not its `profile` string: a `custom` profile can be missing
  exactly those.
- Husky split into a fast `pre-commit` (typecheck + lint + lint-staged) and
  a full `pre-push` (coverage).
- Removed the `sequential-thinking` MCP server; pinned
  `@playwright/mcp@0.0.78`.

### Added

- `tests/smoke-json-schema.sh` — manifest shapes, frontmatter parseability,
  and `claude plugin validate --strict` when the CLI is available.
- `tests/hook-behaviour.sh` — 23 checks driving every hook against a
  throwaway git repo.
- `tests/fixtures/` — vite-vitest-yarn and next-jest-pnpm regression
  fixtures, and `tests/MANUAL-CHECKLIST.md`.

## 0.1.0

Initial extraction of the harness into plugin form. See 0.2.0 for the
defects this release shipped with.
