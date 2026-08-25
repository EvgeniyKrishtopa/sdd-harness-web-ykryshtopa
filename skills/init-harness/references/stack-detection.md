# Stack detection

The one procedure for detecting a project's package manager, framework, and
test runner. `init-harness` runs this once and records the result in
`.claude/harness.json` (see its Step 1 and Step 8). No other skill or hook
re-implements any part of this — they read the manifest instead (Step 8's
schema). This file is also what a skill should point a user to if
`.claude/harness.json` is missing and they want to understand what rerunning
`init-harness` will detect, rather than re-deriving it themselves.

Detection previously lived duplicated, and already drifted, across four
places: `init-harness` knew about `next.config.mjs` but `web-qa`'s copy
didn't, and nothing checked `vite.config.mts`/`vite.config.mjs` at all. This
file is the fix — one text, one set of checks.

## Package manager

Check for a lockfile in the repo root, in this order:

1. `yarn.lock` → `yarn` (run scripts as `yarn <script>`)
2. `package-lock.json` → `npm` (run scripts as `npm run <script>`)
3. `pnpm-lock.yaml` → `pnpm` (run scripts as `pnpm <script>`)

If none exist yet, ask the user which one they want — never guess on an
empty repo.

## Framework

Check for a config file in the repo root, in this order:

1. `next.config.js` / `next.config.ts` / `next.config.mjs` → Next.js.
   Default dev server: `http://localhost:3000`.
2. `vite.config.js` / `vite.config.ts` / `vite.config.mjs` / `vite.config.mts`
   → Vite. Default dev server: `http://localhost:5173`.

If neither is found, stop and ask the user — do not guess a framework onto a
project that has neither. If an existing `dev` script already pins a
different port with `-p`/`--port`, use that instead of the framework default.

## Test runner

Check `package.json` devDependencies for `vitest` or `jest`. If neither is
present, ask the user rather than assuming one.

## Build output directory

Derived from framework, not independently detected: `dist` for Vite, `.next`
for Next.js.

## Script name mapping

Read `package.json`'s `scripts` object and map the real script **keys** to
the manifest's `dev`/`typecheck`/`lint`/`testCoverage` roles. Never invent a
script name that isn't there — if the mapping isn't obvious (e.g. no script
looks like a typecheck or coverage run), ask the user which script to use,
or whether one needs to be added first.

One further role is **optional**: `testIntegration`, the separate script
some projects use for integration tests that need a database or a running
server. Look for a key like `test:integration`, `test:it`, `integration`, or
`e2e:integration`. Found one → map it. Found none → write no
`testIntegration` key at all and **don't ask**: most projects run their
integration tests in the same command as the rest, and a question about a
script that shouldn't exist costs the user more than the key is worth. This
is the opposite of the four roles above, where an unclear mapping is worth a
question.
