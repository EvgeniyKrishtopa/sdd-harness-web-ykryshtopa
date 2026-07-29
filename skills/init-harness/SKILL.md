---
name: init-harness
description: One-time scaffolder that detects the project's framework (Vite or Next.js) and package manager, installs and initializes OpenSpec, writes .claude/docs/git-conventions.md and review-gates.md, writes the single-source-of-truth .claude/harness.json manifest every other skill and hook reads, creates or appends a pointer block to CLAUDE.md/AGENTS.md so that documentation and the auto-commit override are actually discoverable, merges permissions and .claudeignore into the target repo, and installs native git pre-commit/pre-push hooks (Husky). This plugin's Claude Code hooks apply automatically and need no per-project copy. Use once when adding this harness to a new or existing web project.
---

Run this once per repository, before using any other skill in this plugin.

## Step 1 — detect the project

Follow `references/stack-detection.md` for the full procedure: package
manager (lockfile), framework (config file, including the `vite.config.mts`/
`.mjs` and `next.config.mjs` variants), test runner, build output directory,
default dev server URL, and the script-name mapping. This is the single
detection procedure every other skill and hook defers to via the manifest
Step 8 writes below — don't inline a shorter or different version of it here
or anywhere else.

## Step 2 — install and initialize OpenSpec in Expanded (custom) profile

This harness is built on OpenSpec (spec-driven development CLI) — it is not
optional or assumed to already be present. It is also built against
OpenSpec's **Expanded** workflow set, not the default **Core** profile — see
below for why that distinction matters and how to get there safely.

The npm package to install is **`@fission-ai/openspec`** — the bare
`openspec` package name is an unrelated empty squatter package (published as
`0.0.0`, no functionality). Both packages happen to expose a binary named
`openspec`, so once installed the CLI is invoked the same way either way;
the difference only matters at install time.

### 2a — prerequisite

Check the Node version (`node --version`): OpenSpec requires **Node >=
20.19.0**. If it's older, stop and tell the user to upgrade Node before
continuing — don't attempt the install against an unsupported runtime.

### 2b — install and initialize

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

### 2c — check and, if needed, upgrade the workflow profile

`openspec init` sets up the **Core** profile (`propose`, `explore`, `apply`,
`update`, `sync`, `archive`). This harness's gates need the **Expanded**
workflow set (adds `new`, `continue`, `ff`, `bulk-archive`, `verify`,
`onboard`) — Gate 1 (`architecture-review`) is designed to fire once
`design.md` is done but before specs/tasks are drafted, and Gate 2
(`spec-review`) waits for every artifact's step-by-step completion. Neither
point of insertion exists in Core's single-shot `propose` flow.

There is no literal `"expanded"` profile value — in OpenSpec's config schema
`profile` is the enum `core | custom`. Expanded is expressed as
`profile: "custom"` plus the full `workflows` list. The CLI derives
`profile` automatically from which workflows are selected.

**This setting is global, not per-project.** It lives in
`~/.config/openspec/config.json` (or `$XDG_CONFIG_HOME/openspec/config.json`),
not anywhere inside this repo. That means: it isn't committed, a teammate
cloning this repo won't have it just because the repo does, CI never has it
unless configured separately, and changing it on this machine affects
**every other OpenSpec project** the user has, not just this one. Because of
that blast radius, never change it silently.

1. Run `npx openspec config list` and read the current `profile`.
2. If it's already `custom` with the full workflow list, skip to 2d
   (verification) — nothing to change.
3. If it's `core`, explain to the user, plainly, before doing anything:
   - this harness requires the Expanded workflow set to work as designed;
   - the setting is global to their machine, not scoped to this repo;
   - it will change OpenSpec's behavior in their other OpenSpec projects too.
   Then offer two ways to proceed, and let the user pick:
   - **Default**: ask the user to run `npx openspec config profile`
     themselves in their own terminal (it's an interactive multi-select —
     not something to drive non-interactively through the agent's Bash
     tool) and select the full workflow set, then confirm back when done.
   - **Direct write**: only with the user's explicit go-ahead, write
     `~/.config/openspec/config.json` directly with:
     ```json
     {
       "profile": "custom",
       "delivery": "both",
       "workflows": ["propose", "explore", "new", "continue", "apply",
                     "update", "ff", "sync", "archive", "bulk-archive",
                     "verify", "onboard"],
       "featureFlags": {}
     }
     ```
   Do not pick a path or write this file without the user's explicit
   confirmation — this is someone's global environment, not project state.
4. Once the profile is set, run `npx openspec update` in the repo root to
   apply the new workflow selection to this project's `openspec/` instructions.

### 2d — verify, and stop loudly if it didn't take

Re-run `npx openspec config list` and confirm `new`, `continue`, and `verify`
are present in the workflow list. If the profile is still `core` — **stop
the whole init-harness run here** with a clear message explaining that the
gates in `review-gates.md` are designed around the Expanded lifecycle and
will not trigger correctly under Core. Do not continue installation on a
silent fallback to Core.

### 2e — record the outcome

Once Expanded is confirmed, record the fact in `.claude/harness.json` in the
target repo (create the file with just this key if it doesn't exist yet —
Step 8 below fills in the rest of the manifest around it; never overwrite
this key when that step runs):
```json
{ "openspec": { "profile": "custom", "workflows": ["propose", "explore", "new", "continue", "apply", "update", "ff", "sync", "archive", "bulk-archive", "verify", "onboard"] } }
```
This lets `harness-review` (Gate 6) notice later if someone runs
`openspec config reset` and silently drops the project back to Core.

## Step 3 — install native git hooks (not just Claude Code hooks): fast checks on commit, full coverage on push

This plugin's Claude Code hooks (`hooks/hooks.json`, active automatically
while this plugin is enabled — see the note in Step 6) only fire when
**Claude itself** runs `git commit`/`git push` through the Bash tool — they
do nothing if the human commits or pushes directly from a terminal with no
agent involved. That gap needs its own, independent safety net: real git
hooks, so bad commits and pushes are blocked regardless of who or what is
committing.

Do this now, before Step 6 writes `permissions.deny` — that step denies
`npm install`/`add` and equivalents, which would block installing these
tools if done afterward.

Split the checks by cost, matched to how often each hook fires: this
harness commits once per `tasks.md` group (`opsx-apply-git` §4.7), so a
full `test:coverage` run on every `pre-commit` turns into minutes of wait
on every group — multiplied across a whole change. `pre-commit` stays fast
(typecheck + lint + lint-staged); the full coverage run moves to
`pre-push`, where it runs once per push instead of once per commit.

1. If Husky and `lint-staged` aren't already devDependencies, install both
   (`yarn add -D husky lint-staged` / `npm install -D husky lint-staged` /
   `pnpm add -D husky lint-staged`) and run Husky's init (`npx husky init`).
2. Write `.husky/pre-commit` with the detected package manager's commands,
   chained so any failure blocks the commit:
   ```
   <pm> typecheck && <pm> lint && npx lint-staged
   ```
   (e.g. `yarn typecheck && yarn lint && npx lint-staged`, or the npm/pnpm
   equivalents — use whatever script names actually exist in this project's
   `package.json`; don't invent script names that aren't there, ask the user
   if the mapping isn't obvious.) No test run here — that's `pre-push`,
   below.
3. Configure `lint-staged` — in `package.json`'s `"lint-staged"` key, or a
   `.lintstagedrc.json` if the project already has one of those instead —
   to run the project's lint/format tooling against staged files only, e.g.
   for ESLint: `{"*.{ts,tsx}": "eslint --fix"}`. This is what actually keeps
   `pre-commit` fast: `<pm> lint` above still runs the full project-wide
   lint as a correctness gate, while `lint-staged` auto-fixes and re-stages
   only the files this commit actually touches — ask the user for the exact
   glob/command if the project's lint tooling isn't obvious from
   `package.json`.
4. Write `.husky/pre-push` with the full coverage run:
   ```
   <pm> test:coverage
   ```
   (e.g. `yarn test:coverage`, or the npm/pnpm equivalent.)
5. Do not overwrite an existing `.husky/pre-commit` or `.husky/pre-push`
   that already has content — read each first, and only append/merge the
   missing checks in, the same "never clobber existing config" rule used
   for merges later in this skill.
6. Confirm both hooks are executable (`chmod +x .husky/pre-commit
   .husky/pre-push` if needed).

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

Do not silently overwrite either file on a re-run of this skill — the same
"never clobber existing config" rule this skill already applies to hooks
(Step 3), permissions (Step 6), `.claudeignore` (Step 7), and CLAUDE.md
(Step 9) also applies here, even though these two are fully generated files
rather than merge targets. If a file already exists, read it first:
- If its content is identical to what this step would generate (modulo the
  substituted package-manager commands and coverage threshold), there's
  nothing to do — leave it.
- If it differs — a changed coverage threshold, a package-manager switch,
  or hand-edits the user made to the doc directly — tell the user
  specifically what's different and ask before overwriting. Never replace a
  file the user may have customized without them seeing what would change.
- Only write straight over the file with no confirmation when it doesn't
  exist yet.

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
this plugin's `hooks/hooks.json`, matcher `Read|Grep|Glob` — see the note in
Step 6, nothing to install here) that reads `.claudeignore` and denies
matching reads — see `references/claudeignore-template.md` for the full
explanation and the template content.

1. Write `.claudeignore` from that template (substituting build dir and
   lockfile same as Step 6) — or append missing lines if one already exists.
2. When reporting in Step 10, state plainly that `.claudeignore` is a
   convenience/noise-reduction layer enforced by this plugin's own hook, not
   a Claude Code native feature, and that secrets/destructive-command
   protection lives in `permissions.deny` instead.

## Step 8 — write the full stack manifest: `.claude/harness.json`

This is the single machine-readable source of truth every other skill
(`opsx-apply-git`, `web-qa`, `test-coverage`, `harness-review`) and this
plugin's `PostToolUse` typecheck hook read instead of re-detecting the stack
themselves. Merge into the file Step 2e already started (it may already
contain just the `openspec` key) — never overwrite that key, only add the
rest around it:

```json
{
  "version": 1,
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
  "openspec": { "profile": "custom", "workflows": ["propose", "explore", "new", "continue", "apply", "update", "ff", "sync", "archive", "bulk-archive", "verify", "onboard"] },
  "models": {
    "architecture": "claude-opus-5",
    "spec": "claude-sonnet-5",
    "webQa": "claude-haiku-4-5",
    "code": "claude-sonnet-5",
    "testCoverage": "claude-haiku-4-5",
    "harness": "claude-haiku-4-5",
    "default": "claude-sonnet-5"
  }
}
```

Field notes:
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
- `openspec` — already written by Step 2e; carry it over unchanged.
- `models` — one entry per review-gate agent plus a `default` fallback. Seed
  it with the values shown above, not with whatever each `agents/*.md`
  currently declares in its own frontmatter — every gate skill
  (`architecture-review`, `spec-review`, `code-review`, `test-coverage`,
  `harness-review`, `web-qa`) reads its own key from this manifest and
  passes it as the `Agent` tool's `model` override, so this is the actual
  place a user changes which model a gate runs on, not the agent files
  themselves. Only depart from the seeded defaults if the user asks for a
  different tier or doesn't have access to one of these models.

Every field must be a real detected or user-confirmed value. Never leave a
literal placeholder token in the written file — if a value can't be
determined, ask the user rather than guessing.

## Step 9 — create or append CLAUDE.md's harness pointer block

`.claude/docs/*.md` (Step 5) is **not** loaded into context automatically the
way `CLAUDE.md`/`AGENTS.md` is. Without a pointer from the root instruction
file, no session ever reads `git-conventions.md` or `review-gates.md` unless
`opsx-apply-git` happens to read them itself — and more importantly, this
user's global instructions only recognize an auto-commit override
("commit without being asked") when it is *referenced from the project's
CLAUDE.md*. `opsx-apply-git` §4.7 and §5.3 rely on `git-conventions.md`
being exactly that override, at group and archive boundaries. Without this
step, that override is undiscoverable, and a fresh session should fall back
to asking before every commit instead of trusting it.

1. Check for `CLAUDE.md`, or `AGENTS.md` if that's what this project already
   uses instead. If **neither exists**, create a minimal `CLAUDE.md`
   containing just the block below.
2. If **one already exists**, append the block below to the end of it —
   never overwrite or reorder existing content, the same merge rule used for
   every other file this skill touches.
3. Block content (prefer `@`-imports if the target Claude Code version
   supports them; otherwise plain links, one line of explanation each — do
   not leave literal placeholder text):

   ```markdown
   ## Harness (sdd-harness-web-ykryshtopa)

   - @.claude/docs/git-conventions.md — branch/commit conventions. This is
     also the documented authorization for `opsx-apply-git` to commit
     automatically at task-group and archive boundaries (its §4.7/§5.3) —
     without this reference, that override isn't discoverable and shouldn't
     be assumed.
   - @.claude/docs/review-gates.md — the six automated review gates and
     their order.
   - @.claude/harness.json — detected stack (framework, package manager,
     test runner, coverage threshold). Every skill and hook in this harness
     reads from here; do not re-detect any of it.
   ```

4. Keep the block short. Gate 6 (`harness-review`) already checks that the
   root instruction file stays under roughly 200 lines — this step should
   never be the reason that budget gets exceeded.

## Step 10 — report

Summarize what was detected (framework, package manager, test runner),
confirm OpenSpec is initialized, state the coverage threshold chosen, and
list the files written — including confirming the native pre-commit and
pre-push hooks are now in place (Step 3), noting that this plugin's Claude Code hooks are
already active with nothing to install (Step 6), the
permissions/`.claudeignore` distinction from Steps 6-7 (what
`permissions.deny` actually enforces vs. what the `.claudeignore` guard hook
covers), that `.claude/harness.json` (Step 8) is now the source every other
skill reads for stack details, and whether `CLAUDE.md`/`AGENTS.md` (Step 9)
was created or appended to — say plainly that this is required for the
auto-commit override at group/archive boundaries to apply. Tell the user
their harness is ready and that `opsx-propose-review` is the next command to
run when they want to start their first spec-driven change.
