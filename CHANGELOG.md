# Changelog

This plugin declares a `version` in `.claude-plugin/plugin.json`, which
means Claude Code pins installs to that string: pushing commits without
bumping it delivers nothing to anyone who already installed. Every release
therefore gets a version bump and an entry here. See "Versioning and
releases" in the README for the procedure.

Versions follow semver. Before 1.0.0, breaking changes land in the minor
position.

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
