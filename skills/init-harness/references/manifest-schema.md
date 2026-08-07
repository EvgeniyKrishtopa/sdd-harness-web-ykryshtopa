# Step 8 — `.claude/harness.json`, the full schema and what each key means

Merge into the file Step 2e already started (it may already contain just the
`openspec` key) — never overwrite that key, only add the rest around it.

```json
{
  "version": 1,
  "harnessVersion": "0.3.0",
  "toolchainVerifiedAt": "2026-08-01T12:00:00Z",
  "framework": "vite",
  "packageManager": "yarn",
  "runCmd": "yarn",
  "testRunner": "vitest",
  "buildDir": "dist",
  "lockfile": "yarn.lock",
  "coverageThreshold": 80,
  "scripts": {
    "dev": "dev",
    "typecheck": "typecheck",
    "lint": "lint",
    "testCoverage": "test:coverage"
  },
  "devServerUrl": "http://localhost:5173",
  "webQaScenariosDir": "tests/web-qa-scenarios",
  "trivialDiffThreshold": 10,
  "trivialDiffPaths": ["*.md", "*.css", "*.svg", "public/**"],
  "maxFixAttempts": 2,
  "openspec": { "profile": "custom", "workflows": ["propose", "explore", "new", "continue", "apply", "update", "ff", "sync", "archive", "bulk-archive", "verify", "onboard"] },
  "models": {
    "architecture": "claude-opus-5",
    "spec": "claude-sonnet-5",
    "webQa": "claude-haiku-4-5",
    "code": "claude-sonnet-5",
    "harness": "claude-haiku-4-5",
    "default": "claude-sonnet-5"
  }
}
```

## Field notes

- `version` — the schema version of *this manifest*. It changes only when the
  shape of this file changes in a way readers have to know about. It is not
  the plugin's version and never stands in for it.
- `harnessVersion` — the version of *the plugin* that last configured this
  repository, read at run time from
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` (Step 0). Write the value
  that command returns; the `"0.3.0"` above is the shape, not a constant to
  copy. Step 8b writes it, not this step, and only once every step of this
  run has succeeded — it is the claim "this repo is fully configured for
  that plugin version",
  and Step 0's branch 2 and Gate 6's checklist item 6 both trust it. A run
  that stopped early leaves the old value (or none) in place.
- `toolchainVerifiedAt` — written by Step 8b, alongside `harnessVersion` and
  under the same rule: only once the three scripts were actually run and
  actually passed. Its absence means they weren't, which is what lets a
  later run tell a proven toolchain from an assumed one.
- `framework`, `packageManager`, `testRunner`, `buildDir`, `lockfile` — the
  values detected in Step 1 (`buildDir` is `dist` for Vite, `.next` for
  Next.js; `lockfile` is whichever of `yarn.lock`/`package-lock.json`/
  `pnpm-lock.yaml` was found).
- `runCmd` — the command prefix used to invoke a `package.json` script
  (`yarn`, `npm run`, or `pnpm`).
- `scripts.*` — the actual script **keys** that exist in this project's
  `package.json` for `dev`, `typecheck`, `lint`, and the coverage-mode test
  run — never invented names. Ask the user if a mapping isn't obvious, the
  same rule Step 3's Husky hook already follows.
- `coverageThreshold` — the number chosen in Step 4.
- `devServerUrl` — the dev server's root URL: `http://localhost:3000`
  (Next.js default) or `http://localhost:5173` (Vite default), unless an
  existing `dev` script already pins a different port with `-p`/`--port`.
- `webQaScenariosDir` — where `web-qa` records/replays Playwright scenarios;
  same don't-ask-unless-raised treatment as `trivialDiffThreshold` below.
- `trivialDiffThreshold` / `trivialDiffPaths` — seed with the values shown
  above; don't ask the user for these unless they raise it. `code-review`
  (Gate 4+5) skips itself, at zero model cost, for a run whose cumulative
  diff changes fewer than `trivialDiffThreshold` lines (`git diff
  --shortstat`) **and** every changed path matches one of
  `trivialDiffPaths` (cost-optimization #36) — a 3-line CSS tweak or a typo
  fix in a `.md` file doesn't need a full review pass. A user who wants a
  stricter or looser bar edits this manifest directly; there's no separate
  prompt for it.
- `maxFixAttempts` — seed with `2`, the same don't-ask-unless-raised
  treatment as `trivialDiffThreshold`. The `debug-loop` skill reads it to
  bound a `web-qa` fix loop or a `code-review` CONFIRMED fix attempt before
  escalating to a human. A user who wants a stricter or looser bar edits
  this manifest directly.
- `openspec` — already written by Step 2e; carry it over unchanged.
- `models` — one entry per review-gate agent plus a `default` fallback. Seed
  it with the values shown above, not with whatever each `agents/*.md`
  currently declares in its own frontmatter — every gate skill
  (`architecture-review`, `spec-review`, `code-review`, `harness-review`,
  `web-qa`) reads its own key from this manifest and passes it as the
  `Agent` tool's `model` override, so this is the actual place a user
  changes which model a gate runs on, not the agent files themselves. There
  is no separate `testCoverage` key: Gate 5 (test-coverage) is folded into
  the same `code-review` delegation as Gate 4 (cost-optimization #33), so it
  runs on `models.code`. Only depart from the seeded defaults if the user
  asks for a different tier or doesn't have access to one of these models.

## Two rules that hold for the whole file

Every field must be a real detected or user-confirmed value. Never leave a
literal placeholder token in the written file — if a value can't be
determined, ask the user rather than guessing.

Two keys are deliberately not written by Step 8: `harnessVersion` and
`toolchainVerifiedAt`. Both are claims about a run that has finished
successfully, and that run hasn't — Step 8b writes them once it passes.
Write every other key at Step 8, because Step 8b verifies exactly the values
that step recorded, not a fresh guess at them.
