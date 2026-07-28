---
name: init-harness
description: One-time scaffolder that detects the project's framework (Vite or Next.js) and package manager, installs and initializes OpenSpec, writes .claude/docs/git-conventions.md and review-gates.md, merges permissions and .claudeignore into the target repo, and installs a native git pre-commit hook (Husky). This plugin's Claude Code hooks apply automatically and need no per-project copy. Use once when adding this harness to a new or existing web project.
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

## Step 3 — install a native git pre-commit hook (not just Claude Code hooks)

This plugin's Claude Code hooks (`hooks/hooks.json`, active automatically
while this plugin is enabled — see the note in Step 6) only fire when
**Claude itself** runs `git commit` through the Bash tool — they do nothing
if the human commits directly from a terminal with no agent involved. That
gap needs its own, independent safety net: a real git pre-commit hook, so
bad commits are blocked regardless of who or what is committing.

Do this now, before Step 6 writes `permissions.deny` — that step denies
`npm install`/`add` and equivalents, which would block installing Husky if
done afterward.

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
   "never clobber existing config" rule used for merges later in this skill.
4. Confirm the hook is executable (`chmod +x .husky/pre-commit` if needed).

## Step 4 — ask the user for the coverage threshold

Ask what minimum test-coverage percentage to enforce (statements/lines/
functions). Default to 80% if they have no preference — do not hardcode a
number without asking; different projects have different baselines.

## Step 5 — write the harness docs

Write `.claude/docs/git-conventions.md` and `.claude/docs/review-gates.md`
into the target repo (see `references/git-conventions-template.md` and
`references/review-gates-template.md` in this skill for the content to
adapt — fill in the detected package manager's commands and the chosen
coverage threshold rather than copying placeholders verbatim).

## Step 6 — merge permissions allow/deny into `.claude/settings.json`

This plugin's `hooks/hooks.json` (commit gate, merge/push guards,
`.claudeignore` enforcement, typecheck-on-edit, session banner) is loaded
automatically for this repo as soon as the plugin is enabled — the same way
its skills and agents are. There is nothing to copy or merge for hooks; do
not write a `hooks` key into the target repo's own `.claude/settings.json`,
and do not maintain a second copy of `hooks/hooks.json` there. A per-project
copy would drift from the plugin's version the first time either one is
edited, and there is no mechanism keeping the two in sync.

What the target repo's own `.claude/settings.json` **does** need is a
`"permissions"` key — that's a project-level setting, not something a plugin
can ship on the project's behalf. Merge `references/permissions-template.md`'s
`allow`/`deny` arrays into the target repo's `.claude/settings.json`,
substituting the detected package manager, build-output directory (`dist`
for Vite, `.next` for Next.js), and lockfile — never overwrite an existing
`permissions` block, merge and de-duplicate entries into it instead. This is
the actually-enforced mechanism for hard blocks (secrets, destructive
commands) — see that file's notes on why the three non-detected package
managers' install commands stay denied regardless of which one this project
uses.

By this point Steps 2 and 3 have already installed OpenSpec and Husky, so
denying further ad-hoc installs here doesn't block anything this skill still
needs to do.

## Step 7 — write `.claudeignore` and its enforcement hook

The user may expect a `.claudeignore` file the way `.gitignore` works.
**Be upfront that this isn't an official Claude Code mechanism** — Claude
Code has no built-in reader for a file of this name; Anthropic's guidance is
to use `permissions.deny` (Step 6) instead. This plugin makes the file
meaningful anyway by pairing it with a `PreToolUse` hook (already active via
this plugin's `hooks/hooks.json`, matcher `Read|Grep` — see the note in
Step 6, nothing to install here) that reads `.claudeignore` and denies
matching reads — see `references/claudeignore-template.md` for the full
explanation and the template content.

1. Write `.claudeignore` from that template (substituting build dir and
   lockfile same as Step 6) — or append missing lines if one already exists.
2. When reporting in Step 8, state plainly that `.claudeignore` is a
   convenience/noise-reduction layer enforced by this plugin's own hook, not
   a Claude Code native feature, and that secrets/destructive-command
   protection lives in `permissions.deny` instead.

## Step 8 — report

Summarize what was detected (framework, package manager, test runner),
confirm OpenSpec is initialized, state the coverage threshold chosen, and
list the files written — including confirming the native pre-commit hook is
now in place (Step 3), noting that this plugin's Claude Code hooks are
already active with nothing to install (Step 6), and the
permissions/`.claudeignore` distinction from Steps 6-7 (what
`permissions.deny` actually enforces vs. what the `.claudeignore` guard hook
covers). Tell the user their harness is ready and that `opsx-propose-review`
is the next command to run when they want to start their first spec-driven
change.
