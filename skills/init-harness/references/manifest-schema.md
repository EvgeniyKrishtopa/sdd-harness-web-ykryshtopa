# Step 8 — `.claude/harness.json`, the full schema and what each key means

Merge into the file Step 2e already started (it may already contain just the
`openspec` key) — never overwrite that key, only add the rest around it.

```json
{
  "version": 1,
  "harnessVersion": "0.3.0",
  "toolchainVerifiedAt": "2026-08-01T12:00:00Z",
  "forge": "github",
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
    "testCoverage": "test:coverage",
    "testIntegration": "test:integration"
  },
  "devServerUrl": "http://localhost:5173",
  "webQaScenariosDir": "tests/web-qa-scenarios",
  "trivialDiffThreshold": 10,
  "trivialDiffPaths": ["*.md", "*.css", "*.svg", "public/**"],
  "maxFixAttempts": 2,
  "openspec": { "profile": "custom", "workflows": ["propose", "explore", "new", "continue", "apply", "update", "ff", "sync", "archive", "bulk-archive", "verify", "onboard"] },
  "disabledRules": [],
  "sizeRouting": { "enabled": true },
  "scaffold": { "enabled": true },
  "makerChecker": { "enabled": false },
  "models": {
    "architecture": "claude-opus-5",
    "spec": "claude-sonnet-5",
    "webQa": "claude-haiku-4-5",
    "code": "claude-sonnet-5",
    "deep": "claude-opus-5",
    "harness": "claude-haiku-4-5",
    "testAuthor": "claude-sonnet-5",
    "clarify": "claude-sonnet-5",
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
- `forge` — which code-hosting forge this repo's `origin` points to:
  `"github"` or `"other"`, the value Step 1's detection determines (see
  `references/forge-detection.md`) and Step 8 writes in with the rest of
  this file — `"other"` covers GitLab, Bitbucket,
  Azure DevOps, and no `origin` at all alike, since this harness's delivery
  step behaves identically (unsupported) on all three of the first group.
  `opsx-apply-git`'s delivery step and `archive-run.md`'s PR-state check
  both read this key instead of assuming GitHub.
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
- `scripts.testIntegration` (added 0.9.0) — **optional**, and the only
  optional key in `scripts`. Write it only when this project keeps its
  integration tests behind a *separate* `package.json` script, the common
  arrangement when they need a database or a running server and don't
  belong in the fast unit run. Most projects have no such script: then omit
  the key entirely — never an empty string, and never a guessed name.
  Without it everything behaves as it did before this key existed;
  `.husky/pre-push` chains only the coverage run and the audit
  (`references/git-hooks.md` step 4), and nothing else in this harness
  looks for it. The cost of filling it in is a longer push, which is the
  point: tests nothing runs are tests nobody finds out about.
- `makerChecker` (added 0.9.0) — `{ "enabled": false }` by default, and
  seeded that way. When `true`, `opsx-apply-git` has the `test-author` agent
  write a task group's tests from the test plan **before** the group's
  implementation exists, and the implementing session writes no tests of its
  own and may not edit the ones it was given (`skills/opsx-apply-git/
  SKILL.md` §3). Off, a group is implemented exactly as it was in 0.8.0 —
  same session, code and tests together. The cost is one extra subagent per
  group with test-plan rows, which is why a project opts in rather than out.
  `models.testAuthor` picks that agent's model, like every other `models.*`
  key.
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
- `disabledRules` — an array of rule codes (`"CR-07"`, `"SR-02"`, `"DR-03"`,
  ...) this project has switched off, keyed against the permanent codes
  listed in `agents/code-reviewer.md`, `agents/spec-reviewer.md`, and
  `agents/deep-reviewer.md`. Seed it as an
  empty array; a user edits this list directly when one rule proves
  consistently unhelpful for their project — no separate prompt for it, the
  same don't-ask-unless-raised treatment as `trivialDiffThreshold` above.
  `code-review` and `spec-review` read this list and pass it to their
  respective agent — and `code-review` passes it to `deep-reviewer` as well
  — which skips findings under any code on it while every other rule in the
  same review keeps running.
- `sizeRouting` — a single `enabled` toggle for the size-based routing
  `opsx-propose-review` runs before a change's artifacts exist: touching
  more than one module, changing the data schema, or changing a contract
  (an API endpoint, an exported signature, a shared type) sends the change
  down the **full** route (every step this version added runs); none of the
  three sends it down the **short** route (`spec-clarify`'s ambiguity sweep
  is skipped, and `spec-review`/`architecture-review` skip their extra
  deliberation pass — never the checklist itself, and never `code-review` or
  test-coverage). Seed as `{"enabled": true}`; a user sets it `false` to
  always take the full route, the same don't-ask-unless-raised treatment as
  `trivialDiffThreshold`. The route itself is recorded per change, in
  `openspec/changes/<change>/.route` — not here; this key only turns the
  assessment on or off.
- `scaffold` (added 0.7.0) — a single `enabled` toggle for the scaffold
  stage: `opsx-scaffold` turning an approved `design.md` into real stub
  files before a change's feature code is written, reviewed by
  `architecture-reviewer`'s scaffold-review mode as Gate 2b. Unlike
  `sizeRouting` above, **the key missing, or `enabled: false`, both mean the
  stage is off** — not the opposite. Seed it `{"enabled": true}` on a fresh
  `init-harness` run, first-time or upgrade alike; never leave it unwritten.
  The reason the absent-key default runs backwards from `sizeRouting`: this
  stage adds a step to the human's own workflow, and a repository last
  configured by an earlier plugin version must not start springing an
  unfamiliar stage on someone the moment they update the plugin, before
  they've run `init-harness` in upgrade mode to actually opt in. The
  per-change verdict itself is computed and recorded separately, in
  `openspec/changes/<change>/.scaffold` — this key only turns the stage on
  or off.
- `models` — one entry per model-backed subagent this plugin delegates to,
  plus a `default` fallback. Seed it with the values shown above, not with
  whatever each `agents/*.md` currently declares in its own frontmatter —
  every skill that delegates to one of these agents (`architecture-review`,
  `spec-review`, `code-review`, `harness-review`, `web-qa`, `spec-clarify`)
  reads its own key from this manifest and passes it as the `Agent` tool's
  `model` override, so this is the actual place a user changes which model a
  delegation runs on, not the agent files themselves. There is no separate
  `testCoverage` key: Gate 5 (test-coverage) is folded into the same
  `code-review` delegation as Gate 4 (cost-optimization #33), so it runs on
  `models.code`. `clarify` is the same kind of entry for the
  `devils-advocate` agent — not a review gate itself, but read and overridden
  the same way. `deep` (added 0.5.0) is the entry for the `deep-reviewer`
  agent, the security/architecture-as-built pass `code-review` spawns only
  when its risk prefilter fires; it is seeded on a larger model than
  `code` precisely because it runs rarely — see
  `skills/code-review/references/deep-review.md`. Only depart from the seeded
  defaults if the user asks for a different tier or doesn't have access to
  one of these models.

## Two rules that hold for the whole file

Every field must be a real detected or user-confirmed value. Never leave a
literal placeholder token in the written file — if a value can't be
determined, ask the user rather than guessing.

Two keys are deliberately not written by Step 8: `harnessVersion` and
`toolchainVerifiedAt`. Both are claims about a run that has finished
successfully, and that run hasn't — Step 8b writes them once it passes.
Write every other key at Step 8, because Step 8b verifies exactly the values
that step recorded, not a fresh guess at them.
