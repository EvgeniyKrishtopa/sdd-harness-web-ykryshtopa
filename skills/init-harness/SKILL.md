---
name: init-harness
description: One-time scaffolder that detects the project's framework (Vite or Next.js) and package manager, installs and initializes OpenSpec, writes .claude/docs/git-conventions.md and review-gates.md, generates hooks.json, and installs a native git pre-commit hook (Husky). Use once when adding this harness to a new or existing web project.
---

Run this once per repository, before using any other skill in this plugin.

## Step 1 — detect the project

1. **Package manager**: check for `yarn.lock` → yarn, `package-lock.json` →
   npm, `pnpm-lock.yaml` → pnpm. If none exist yet, ask the user which one
   they want.
2. **Framework**: check for `next.config.js`/`.ts`/`.mjs` → Next.js;
   otherwise `vite.config.js`/`.ts` → Vite. If neither is found, stop and
   ask the user — do not guess a framework onto a project that has neither.
3. **Test runner**: check devDependencies for `vitest` or `jest`.

## Step 2 — install and initialize OpenSpec

This harness is built on OpenSpec (spec-driven development CLI) — it is not
optional or assumed to already be present.

The npm package to install is **`@fission-ai/openspec`** — the bare
`openspec` package name is an unrelated empty squatter package (published as
`0.0.0`, no functionality). Both packages happen to expose a binary named
`openspec`, so once installed the CLI is invoked the same way either way;
the difference only matters at install time.

1. Check whether `@fission-ai/openspec` is already a devDependency (grep
   `package.json`).
2. If not present, install it as a devDependency using the detected package
   manager (`yarn add -D @fission-ai/openspec` /
   `npm install -D @fission-ai/openspec` / `pnpm add -D @fission-ai/openspec`).
3. Verify the install actually worked — run `npx openspec --version` and
   confirm it prints a real semver, not an empty string or an error. Don't
   just check the binary exists; the squatter package can resolve a bare
   `openspec` install to a no-op binary with no visible failure.
4. Run `npx openspec init` in the repo root if `openspec/` doesn't already
   exist. This creates the `openspec/` workspace (specs, changes,
   instructions) that every gate and the `opsx-*` skills read from.
5. If `openspec/` already exists, run `npx openspec doctor` instead to
   confirm it's healthy rather than re-initializing over existing work.

## Step 3 — ask the user for the coverage threshold

Ask what minimum test-coverage percentage to enforce (statements/lines/
functions). Default to 80% if they have no preference — do not hardcode a
number without asking; different projects have different baselines.

## Step 4 — write the harness docs

Write `.claude/docs/git-conventions.md` and `.claude/docs/review-gates.md`
into the target repo (see `references/git-conventions-template.md` and
`references/review-gates-template.md` in this skill for the content to
adapt — fill in the detected package manager's commands and the chosen
coverage threshold rather than copying placeholders verbatim).

## Step 5 — generate hooks.json

Copy this plugin's `hooks/hooks.json` into the target repo's
`.claude/settings.json` (merge into existing `hooks` key if one already
exists — never overwrite a project's existing hooks wholesale), substituting
the detected package manager's typecheck/lint commands for the placeholder
commands in the template.

## Step 6 — merge permissions allow/deny into `.claude/settings.json`

`hooks.json` alone doesn't cover what Claude is and isn't allowed to run or
read — that's a separate `"permissions"` key (sibling of `"hooks"`, same
file). Merge `references/permissions-template.md`'s `allow`/`deny` arrays
into the target repo's `.claude/settings.json`, substituting the detected
package manager, build-output directory (`dist` for Vite, `.next` for
Next.js), and lockfile — never overwrite an existing `permissions` block,
merge and de-duplicate entries into it instead. This is the actually-enforced
mechanism for hard blocks (secrets, destructive commands) — see that file's
notes on why the three non-detected package managers' install commands stay
denied regardless of which one this project uses.

## Step 7 — write `.claudeignore` and its enforcement hook

The user may expect a `.claudeignore` file the way `.gitignore` works.
**Be upfront that this isn't an official Claude Code mechanism** — Claude
Code has no built-in reader for a file of this name; Anthropic's guidance is
to use `permissions.deny` (step 6) instead. This plugin makes the file
meaningful anyway by pairing it with a `PreToolUse` hook (already in this
plugin's `hooks/hooks.json`, matcher `Read|Grep`) that reads `.claudeignore`
and denies matching reads — see `references/claudeignore-template.md` for
the full explanation and the template content.

1. Write `.claudeignore` from that template (substituting build dir and
   lockfile same as step 6) — or append missing lines if one already exists.
2. Confirm the `Read|Grep` hook from `hooks/hooks.json` was included in
   step 5's merge (it lives in the same file, so this should already be
   covered — just don't drop it if the target repo's existing `hooks.json`
   required a manual merge).
3. When reporting in step 9, state plainly that `.claudeignore` is a
   convenience/noise-reduction layer enforced by this plugin's own hook, not
   a Claude Code native feature, and that secrets/destructive-command
   protection lives in `permissions.deny` instead.

## Step 8 — install a native git pre-commit hook (not just Claude Code hooks)

`hooks/hooks.json` above only fires when **Claude itself** runs `git commit`
through the Bash tool — it does nothing if the human commits directly from
a terminal with no agent involved. That gap needs its own, independent
safety net: a real git pre-commit hook, so bad commits are blocked
regardless of who or what is committing.

1. If Husky isn't already a devDependency, install it
   (`yarn add -D husky` / `npm install -D husky` / `pnpm add -D husky`) and
   run its init (`npx husky init`).
2. Write `.husky/pre-commit` with the detected package manager's commands,
   chained so any failure blocks the commit:
   ```
   <pm> typecheck && <pm> lint && <pm> test:coverage
   ```
   (e.g. `yarn typecheck && yarn lint && yarn test:coverage`, or the npm/pnpm
   equivalents — use whatever script names actually exist in this project's
   `package.json`; don't invent script names that aren't there, ask the user
   if the mapping isn't obvious.)
3. Do not overwrite an existing `.husky/pre-commit` that already has content
   — read it first, and only append/merge the missing checks in, the same
   "never clobber existing config" rule as step 5's hooks.json merge.
4. Confirm the hook is executable (`chmod +x .husky/pre-commit` if needed).

## Step 9 — report

Summarize what was detected (framework, package manager, test runner),
confirm OpenSpec is initialized, state the coverage threshold chosen, and
list the files written — including confirming the native pre-commit hook is
now in place (step 8), separately from the Claude Code `hooks.json` merge
(step 5), and the permissions/`.claudeignore` distinction from steps 6-7 (what
`permissions.deny` actually enforces vs. what the `.claudeignore` guard hook
covers). Tell the user their harness is ready and that `opsx-propose-review`
is the next command to run when they want to start their first spec-driven
change.
