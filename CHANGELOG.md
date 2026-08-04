# Changelog

This plugin declares a `version` in `.claude-plugin/plugin.json`, which
means Claude Code pins installs to that string: pushing commits without
bumping it delivers nothing to anyone who already installed. Every release
therefore gets a version bump and an entry here. See "Versioning and
releases" in the README for the procedure.

Versions follow semver. Before 1.0.0, breaking changes land in the minor
position.

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
