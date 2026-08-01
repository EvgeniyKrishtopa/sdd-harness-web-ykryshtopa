---
name: init-harness
description: Scaffolds this harness into a repository, and upgrades a repository an earlier version of the plugin already set up. Detects the project's framework (Vite or Next.js) and package manager, installs and initializes OpenSpec, writes .claude/docs/git-conventions.md and review-gates.md, writes the single-source-of-truth .claude/harness.json manifest every other skill and hook reads, creates or appends a pointer block to CLAUDE.md/AGENTS.md so that documentation and the auto-commit override are actually discoverable, merges permissions and .claudeignore into the target repo, and installs native git pre-commit/pre-push hooks (Husky). This plugin's Claude Code hooks apply automatically and need no per-project copy. Use when adding this harness to a new or existing web project, and again after "/plugin update" — "set up the harness", "init the harness here", "I just updated the plugin", "bring this repo up to the new harness version".
---

Run this when adding the harness to a repository, and again after the plugin
itself is updated — Step 0 decides which of the two is happening. Run it
before using any other skill in this plugin.

## Step 0 — first-time install, or upgrade of a repo an earlier version set up?

This skill used to be a one-shot scaffolder. It isn't anymore: every release
that adds a file to the target repo (see the inventory below) has to reach
repositories that were set up by an earlier version, not just new ones.
`/plugin update` refreshes the skills, agents, and hooks — everything that
lives *in the plugin*. Nothing that lives *in the repository* changes until
this skill runs again. Deciding which mode to run in is therefore the first
thing that happens, before any detection or any question to the user.

Read the plugin's own version and the version this repo was last set up with:

```bash
plugin_version="$(jq -r '.version' "${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json")"
repo_version="$(jq -r '.harnessVersion // empty' .claude/harness.json 2>/dev/null)"
```

Never hardcode the plugin version in this skill's text — it is read from
`.claude-plugin/plugin.json` through `${CLAUDE_PLUGIN_ROOT}` every time, so
it cannot drift away from the manifest at the next version bump. Note that
`.claude/harness.json`'s `"version": 1` is a *different* number: it is the
schema version of the manifest itself, it is not the plugin's version, and
the two are never compared against each other or collapsed into one field.

Then take exactly one of these four branches:

1. **`.claude/harness.json` doesn't exist** → FIRST-TIME INSTALL. Run Steps
   1-10 below as written.
2. **`harnessVersion` equals `plugin_version`** → nothing to do. Say so —
   naming the version — and stop without touching anything. (Re-running the
   whole questionnaire against an already-configured repo, which is what
   this skill did before, wastes the user's time re-answering questions the
   manifest already holds.) If the user explicitly asks for a re-run anyway
   — to repair a file they deleted, say — run the upgrade-mode step list.
3. **`harnessVersion` is absent, or lower than `plugin_version`** → UPGRADE
   MODE, below. Absent means the repo was set up by a version older than the
   one that introduced this field, so it is treated as the oldest possible
   version, not as a fresh install.
4. **`harnessVersion` is *higher* than `plugin_version`** → the installed
   plugin is older than the one that configured this repo. Say so and stop.
   Do not "upgrade" downward: rewriting the manifest to the older version
   would silently claim the repo lost features it still has.

Compare versions as versions, not as strings: `0.10.0` sorts *below* `0.9.0`
lexically. Use `sort -V` (or compare the three numeric components) —

```bash
older="$(printf '%s\n%s\n' "$repo_version" "$plugin_version" | sort -V | head -1)"
```

`$repo_version` is behind when it isn't equal to `$plugin_version` and is
the `$older` of the two.

### The file inventory this skill owns

Upgrade mode walks this list; so does Gate 6 when it checks for drift. Every
future release that teaches this skill to write a new file into the target
repo **must add it here in the same commit** — a file that exists only in
the first-time path reaches new repositories and no one else, which is the
whole failure this step exists to prevent.

| Path | Written by | Merge rule |
| --- | --- | --- |
| `openspec/` workspace | Step 2b | created by `openspec init`; never re-initialized over existing work |
| `.husky/pre-commit`, `.husky/pre-push` | Step 3 | append missing checks, never clobber |
| `.claude/docs/git-conventions.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/docs/review-gates.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/settings.json` (`permissions` only) | Step 6 | merge and de-duplicate entries |
| `.claudeignore` | Step 7 | append missing lines |
| `.claude/harness.json` | Steps 2e, 8 | merge keys; never drop keys already there |
| `CLAUDE.md` / `AGENTS.md` pointer block | Step 9 | append missing lines only |

### Upgrade mode

Run only the steps that create or extend files, and only for what is
actually missing. Concretely:

- **Skip every question the manifest already answers.** The coverage
  threshold (Step 4), the detected framework, package manager, test runner,
  build dir, lockfile, and script names (Step 1) are all in
  `.claude/harness.json` already — read them from there. Only detect, or
  ask, what the manifest doesn't have (a key added by a newer version, or
  one a user removed).
- **Leave the global OpenSpec config alone.** Step 2c changes a setting that
  is global to the user's machine and affects their other projects. In
  upgrade mode, run `npx openspec config list` and check the workflow list
  (Step 2c's own check): if `new`, `continue`, and `verify` are all present,
  there is nothing to do — do not re-prompt, and do not re-write the file.
  Only if one is genuinely missing does Step 2c's normal conversation apply.
- **Walk the inventory above** and apply each row's merge rule: create what
  is absent, append what is missing from what exists, and never overwrite a
  file the user may have edited without showing them the diff first. This is
  the rule this skill already follows everywhere; upgrade mode adds no new
  license to overwrite.
- **Verify the toolchain** — Step 8b runs in upgrade mode too. A script the
  project renamed since the repo was set up is exactly the kind of drift an
  upgrade should surface.
- **Then write `harnessVersion`** (Step 8), and only then. If any step
  stopped — a missing workflow, a failing toolchain check, a diff the user
  declined — leave `harnessVersion` at its old value. A version number
  claiming an upgrade that didn't finish is worse than no version number:
  the next run would skip via branch 2 above.
- **Report what changed** (Step 10): the version transition
  (`<old or "unversioned"> → <new>`), each file created, each file appended
  to, and each file left alone. "Already up to date" is a real and common
  outcome — say it plainly rather than implying work happened.

Upgrade mode is the *only* way a repo picks up a new release's files. Do not
add automatic migration to `SessionStart` or any other hook: writing into the
user's repository without them asking is something this harness does nowhere
else. Version drift is *detected* automatically (Gate 6, checklist item 6)
and *fixed* on command.

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

**Check the workflow list, not the `profile` string.** `profile: custom`
only means the user picked their own selection — it says nothing about
*which* workflows are in it. A machine can sit at `profile: custom` with,
say, `propose, explore, continue, apply, update, sync, archive` — a
perfectly valid custom profile that is still missing `new` and `verify`,
and so still can't run Gates 1-2 at their designed insertion points. That
state is common (it's what a partial pass through the interactive picker
leaves behind) and it must be treated exactly like `core`.

The workflows this harness requires are **`new`, `continue`, `verify`**.
The rest of the Expanded set (`ff`, `bulk-archive`, `onboard`) is nice to
have and not worth blocking on.

1. Run `npx openspec config list` and read the `workflows` list (not just
   `profile`).
2. If `new`, `continue` and `verify` are all present, skip to 2d
   (verification) — nothing to change, whatever `profile` says.
3. If any of the three is missing, explain to the user, plainly, before
   doing anything — naming which ones are missing:
   - this harness requires the Expanded workflow set to work as designed;
   - the setting is global to their machine, not scoped to this repo;
   - it will change OpenSpec's behavior in their other OpenSpec projects too.
   Then offer two ways to proceed, and let the user pick. There is no third
   way: `openspec config profile` accepts exactly one preset shortcut,
   `core` (verified against @fission-ai/openspec 1.7.0 — any other preset
   name exits with "Unknown profile preset"), and outside a TTY it refuses
   to run at all with "Interactive mode required". So the Expanded set can
   only be reached by a human at a prompt, or by writing the file.
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

Re-run `npx openspec config list` and confirm `new`, `continue`, and
`verify` are all present in the workflow list. If any of them is still
missing — **stop the whole init-harness run here**, naming the missing
workflows, with a clear message explaining that the gates in
`review-gates.md` are designed around the Expanded lifecycle and will not
trigger correctly without them.

Key the stop on the missing workflows, **not** on `profile == "core"`. A
run that keys on the profile string sails straight past the most likely
failure — a `custom` profile whose selection is incomplete — and installs a
harness whose first two gates have nowhere to attach.

### 2e — record the outcome

Once the required workflows are confirmed, record what `openspec config
list` **actually reported** in `.claude/harness.json` in the target repo
(create the file with just this key if it doesn't exist yet — Step 8 below
fills in the rest of the manifest around it; never overwrite this key when
that step runs):
```json
{ "openspec": { "profile": "custom", "workflows": ["propose", "explore", "new", "continue", "apply", "update", "ff", "sync", "archive", "bulk-archive", "verify", "onboard"] } }
```
The list above is the shape, not the value to copy: write the real
`profile` and the real `workflows` array this machine reports. Writing an
idealised list defeats the point — Gate 6 compares this key against live
config to notice if someone later runs `openspec config reset` or trims the
selection, and a hardcoded "everything" list makes every such regression
look like a match.

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
harness commits once per `tasks.md` group (`opsx-apply-git` §3), so a
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

This plugin's `hooks/hooks.json` (commit/merge/push guards,
`.claudeignore` enforcement, typecheck-before-stop, session banner) is loaded
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
(`opsx-apply-git`, `web-qa`, `code-review`, `harness-review`) and this
plugin's `Stop` typecheck hook read instead of re-detecting the stack
themselves. Merge into the file Step 2e already started (it may already
contain just the `openspec` key) — never overwrite that key, only add the
rest around it:

```json
{
  "version": 1,
  "harnessVersion": "0.3.0",
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
  "trivialDiffThreshold": 10,
  "trivialDiffPaths": ["*.md", "*.css", "*.svg", "public/**"],
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

Field notes:
- `version` — the schema version of *this manifest*. It changes only when the
  shape of this file changes in a way readers have to know about. It is not
  the plugin's version and never stands in for it.
- `harnessVersion` — the version of *the plugin* that last configured this
  repository, read at run time from
  `${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` (Step 0). Write the value
  that command returns; the `"0.3.0"` above is the shape, not a constant to
  copy. Write it **last**, only once every step of this run has succeeded —
  it is the claim "this repo is fully configured for that plugin version",
  and Step 0's branch 2 and Gate 6's checklist item 6 both trust it. A run
  that stopped early leaves the old value (or none) in place.
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
- `trivialDiffThreshold` / `trivialDiffPaths` — seed with the values shown
  above; don't ask the user for these unless they raise it. `code-review`
  (Gate 4+5) skips itself, at zero model cost, for a run whose cumulative
  diff changes fewer than `trivialDiffThreshold` lines (`git diff
  --shortstat`) **and** every changed path matches one of
  `trivialDiffPaths` (cost-optimization #36) — a 3-line CSS tweak or a typo
  fix in a `.md` file doesn't need a full review pass. A user who wants a
  stricter or looser bar edits this manifest directly; there's no separate
  prompt for it.
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
  asks for a
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
CLAUDE.md*. `opsx-apply-git` §3 and §5.3 rely on `git-conventions.md`
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
     automatically at task-group and archive boundaries (its §3/§5.3) —
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

In upgrade mode, report the shorter form Step 0 describes — version
transition, files created, files appended to, files left alone — not the
full first-install summary below, which mostly restates what the user
already has.

For a first-time install: summarize what was detected (framework, package manager, test runner),
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

Either mode: mention that after a future `/plugin update`, running this skill
again is what brings this repository's own files up to the new version — the
plugin update alone doesn't, and Gate 6 will flag the gap in the meantime.
