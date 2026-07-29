# Fixture: next-jest-pnpm

Minimal, real Next.js (App Router) + TypeScript + Jest + pnpm project. Used by
`tests/MANUAL-CHECKLIST.md` to manually regression-test this plugin against
its other supported stack combination, on a repository the plugin itself
never touched before.

This directory is a **fixture**, not part of the plugin's own build — nothing
in `skills/`, `agents/`, or `hooks/` reads it. To use it:

1. Copy this directory somewhere outside `sdd-harness-web-ykryshtopa`
   (the plugin must be tested against a repo it doesn't already live inside).
2. `cd` into the copy and `git init && git add -A && git commit -m "init fixture"`.
3. Install/enable this plugin there (local marketplace path or however you
   normally install a dev build).
4. `pnpm install` (needs real network/registry access — this fixture ships
   a real `package.json`, but no vendored `node_modules`).
5. Follow `tests/MANUAL-CHECKLIST.md`.

## What `init-harness` (Step 1 / `stack-detection.md`) should detect here

| Signal            | Expected value                    |
|--------------------|------------------------------------|
| lockfile           | `pnpm-lock.yaml` → package manager `pnpm` |
| framework config   | `next.config.js` → Next.js         |
| default dev server | `http://localhost:3000`            |
| test runner        | `jest` (devDependency)             |
| build output dir   | `.next`                            |
| script: dev        | `dev`                              |
| script: typecheck  | `typecheck`                        |
| script: lint       | `lint`                             |
| script: coverage   | `test:coverage`                    |

## Why it has real source and a real test

`src/utils/sum.ts` + `src/utils/sum.test.ts` exist so Gate 5
(`test-coverage`, triggered by "source changed OR tests changed") and Gate 4
(`code-review`) have something non-trivial to look at, and so `pnpm
typecheck` / `pnpm test:coverage` are real, runnable commands rather than
no-ops. `src/app/page.tsx` / `src/app/layout.tsx` are the minimum App Router
shape needed for `pnpm dev` to serve an actual page for Gate 3 (`web-qa`) to
drive with Playwright MCP.

This fixture intentionally differs from `vite-vitest-yarn` on every axis the
harness is meant to generalize across (framework, package manager, test
runner) — running the same checklist against both is what actually exercises
`stack-detection.md` rather than one hardcoded path through it.
