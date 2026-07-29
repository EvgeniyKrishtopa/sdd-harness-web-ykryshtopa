# Fixture: vite-vitest-yarn

Minimal, real Vite + React + TypeScript + Vitest + yarn project. Used by
`tests/MANUAL-CHECKLIST.md` to manually regression-test this plugin against
one of its two supported stack combinations end to end, on a repository the
plugin itself never touched before.

This directory is a **fixture**, not part of the plugin's own build — nothing
in `skills/`, `agents/`, or `hooks/` reads it. To use it:

1. Copy this directory somewhere outside `sdd-harness-web-ykryshtopa`
   (the plugin must be tested against a repo it doesn't already live inside).
2. `cd` into the copy and `git init && git add -A && git commit -m "init fixture"`.
3. Install/enable this plugin there (local marketplace path or however you
   normally install a dev build).
4. `yarn install` (needs real network/registry access — this fixture ships
   a real `package.json`, but no vendored `node_modules`).
5. Follow `tests/MANUAL-CHECKLIST.md`.

## What `init-harness` (Step 1 / `stack-detection.md`) should detect here

| Signal            | Expected value                    |
|--------------------|------------------------------------|
| lockfile           | `yarn.lock` → package manager `yarn` |
| framework config   | `vite.config.ts` → Vite            |
| default dev server | `http://localhost:5173`            |
| test runner        | `vitest` (devDependency)           |
| build output dir   | `dist`                             |
| script: dev        | `dev`                              |
| script: typecheck  | `typecheck`                        |
| script: lint       | `lint`                             |
| script: coverage   | `test:coverage`                    |

## Why it has real source and a real test

`src/utils/sum.ts` + `src/utils/sum.test.ts` exist so `code-review`'s Gate 4
section and its Gate 5 section (triggered by "source changed OR tests
changed", merged into the same delegation as Gate 4) both have something
non-trivial to look at, and so `yarn typecheck` / `yarn test:coverage` are
real, runnable commands rather than no-ops. `src/App.tsx` / `src/main.tsx` are the minimum needed for `yarn dev`
to serve an actual page for Gate 3 (`web-qa`) to drive with Playwright MCP.
