---
name: init-harness
description: Scaffolds this harness into a repository, and upgrades a repository an earlier version of the plugin already set up. Detects the project's framework (Vite or Next.js) and package manager, installs and initializes OpenSpec, seeds openspec/config.yaml with the project's context and artifact rules so changes are drafted knowing what this project is, writes .claude/docs/git-conventions.md and review-gates.md, writes the single-source-of-truth .claude/harness.json manifest every other skill and hook reads, creates or appends a pointer block to CLAUDE.md/AGENTS.md so that documentation and the auto-commit override are actually discoverable, merges permissions and .claudeignore into the target repo, and installs native git pre-commit/pre-push hooks (Husky), then proves the detected typecheck/lint/test scripts actually run and pass before declaring the repo configured. This plugin's Claude Code hooks apply automatically and need no per-project copy. Use when adding this harness to a new or existing web project, and again after "/plugin update" — "set up the harness", "init the harness here", "I just updated the plugin", "bring this repo up to the new harness version".
---

Run this when adding the harness to a repository, and again after the plugin
itself is updated — Step 0 decides which of the two is happening. Run it
before using any other skill in this plugin.

## Step 0 — first-time install, or upgrade of a repo an earlier version set up?

This skill used to be a one-shot scaffolder. It isn't anymore: every release
that adds a file to the target repo (see the inventory in
`references/upgrade-mode.md`) has to reach repositories that were set up by
an earlier version, not just new ones.
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

### Upgrade mode, and the file inventory this skill owns

On branch 3, **read `references/upgrade-mode.md` now and follow it** — it
holds the procedure (which steps run, which questions are skipped, when
`harnessVersion` may be written) and the inventory of every file this skill
writes into a target repo, with each one's merge rule.

That inventory is the contract: every future release that teaches this skill
to write a new file **must add it there in the same commit**, or the file
reaches new repositories and no existing one. Gate 6 reads the same table
when it checks for drift.

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

1. Run `npx openspec config list` and read the **`workflows` list, not the
   `profile` string** — `profile: custom` says only that the user picked
   their own selection, not which workflows are in it, and an incomplete
   `custom` selection is the most likely failure here.
2. If `new`, `continue` and `verify` are all present, skip to 2d — nothing
   to change, whatever `profile` says.
3. If any of the three is missing, **read `references/openspec-profile.md`
   now and follow it**. Do not improvise this one: the setting is global to
   the user's machine and affects their other OpenSpec projects, so it is
   never changed silently or without their explicit confirmation.

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

### 2f — seed `openspec/config.yaml` with this project's context and rules

`openspec init` left this file at its defaults, which means every change in
this repo would be drafted by an agent that knows nothing about the project.
Seeding it is what makes Gates 1 and 2 review artifacts that were generated
with context rather than blind.

**Read `references/openspec-config-seed.md` now and follow it.** Note that
it asks the user one question — three to five lines on what the project
actually is — so this step is not fully unattended.

## Step 3 — install native git hooks (not just Claude Code hooks): fast checks on commit, full coverage on push

This plugin's Claude Code hooks only fire when **Claude itself** commits or
pushes through the Bash tool — they do nothing when the human commits from a
terminal. Native git hooks close that gap.

Do this now, **before Step 6** writes `permissions.deny` — that step denies
`npm install`/`add` and equivalents, which would block installing Husky and
`lint-staged` if this were done afterward.

**Read `references/git-hooks.md` now and follow it.** It covers both hook
files, the `lint-staged` config, the package-manager-specific audit command
(including the yarn 1 vs yarn 2+ split), and the never-clobber rule for a
repo that already has hooks.

## Step 4 — ask the user for the coverage threshold

Ask what minimum test-coverage percentage to enforce (statements/lines/
functions). Default to 80% if they have no preference — do not hardcode a
number without asking; different projects have different baselines.

## Step 5 — write the harness docs

Write `.claude/docs/git-conventions.md`, `.claude/docs/review-gates.md`, and
`.claude/docs/laziness-ladder.md` into the target repo from
`references/git-conventions-template.md`, `references/review-gates-template.md`,
and `references/laziness-ladder-template.md` in this skill.

Only one of the three carries placeholders. Substitute **all four** of them —
a `{{...}}` left in a written file is a bug the user sees, and the template
says so itself at the bottom:

| Template | Substitute |
| --- | --- |
| `review-gates-template.md` | `{{PACKAGE_MANAGER}}`, `{{COVERAGE_THRESHOLD}}` (Step 4's answer), `{{FRAMEWORK}}`, `{{TEST_RUNNER}}` — all from Step 1's detection and the manifest |
| `git-conventions-template.md` | nothing — it has no placeholders; copy as-is |
| `laziness-ladder-template.md` | nothing; copy as-is |

Keep this table and the templates in step: a release that adds a placeholder
to one of these files **must** add it here in the same commit, the same rule
Step 0's file inventory follows. A placeholder listed in a template but not
here is the drift that ships a literal `{{FRAMEWORK}}` into someone's repo.

Do not silently overwrite any of the three on a re-run of this skill — the
same "never clobber existing config" rule this skill already applies to hooks
(Step 3), permissions (Step 6), `.claudeignore` (Step 7), and CLAUDE.md
(Step 9) also applies here, even though these are fully generated files
rather than merge targets. If a file already exists, read it first:
- If its content is identical to what this step would generate (modulo the
  substituted package-manager commands and coverage threshold), there's
  nothing to do — leave it.
- If it differs — a changed coverage threshold, a package-manager switch,
  or hand-edits the user made to the doc directly — tell the user
  specifically what's different and ask before overwriting. Never replace a
  file the user may have customized without them seeing what would change.
- Only write straight over the file with no confirmation when it doesn't exist yet.

Also seed this repo's continuity files — new in both first-install and
upgrade mode, since a repo set up by an earlier version never got them:

- Write `CONTEXT.md` from `references/context-template.md` if absent — same never-overwrite rule as below; starts empty, fills in as terms come up.
- Write an initial `PROGRESS.md` at the repo root from
  `references/progress-template.md` if one doesn't already exist — same
  never-overwrite rule as above. A fresh file starts with no current change,
  no next steps, and a clock-in of "now"; after this point only
  `opsx-apply-git` touches it, at its own run boundaries (see
  `references/progress-template.md`).
- Write `.gitattributes` with `PROGRESS.md merge=union` — append the line if
  the file exists without it, leave everything else in it alone.
  `PROGRESS.md` is the one file every task-group branch in this harness's
  branch-per-group workflow can touch, so without this, every group's PR
  would conflict on it. Nothing else in this harness needs `merge=union` —
  in particular not `docs/decisions/`, whose whole design point is that two
  branches produce two different files instead of contending for one (see
  `references/decision-template.md`).
- Check whether the project already has a `docs/adr/` directory. If it does,
  tell the user to keep using it and don't create a competing
  `docs/decisions/` alongside it. If it doesn't, there's nothing to create
  yet — `docs/decisions/` comes into existence the first time
  `opsx-apply-git` (§3 Case B) actually writes a decision that outlives its
  change, not before.

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
substituting all four of its placeholders — `{{PACKAGE_MANAGER}}`,
`{{BUILD_DIR}}` (`dist` for Vite, `.next` for Next.js), `{{SERVE_SCRIPT}}`
(`preview` for Vite, `start` for Next.js), and `{{LOCKFILE}}` — never
overwrite an existing
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

1. Write `.claudeignore` from that template, substituting its two
   placeholders — `{{BUILD_DIR}}` and `{{LOCKFILE}}`, same values as Step 6
   — or append missing lines if one already exists.
2. When reporting in Step 10, state plainly that `.claudeignore` is a
   convenience/noise-reduction layer enforced by this plugin's own hook, not
   a Claude Code native feature, and that secrets/destructive-command
   protection lives in `permissions.deny` instead.

## Step 8 — write the full stack manifest: `.claude/harness.json`

This is the single machine-readable source of truth every other skill
(`opsx-apply-git`, `web-qa`, `code-review`, `harness-review`) and this
plugin's `Stop` typecheck hook read instead of re-detecting the stack
themselves.

**Read `references/manifest-schema.md` now and follow it** — it holds the
full key list and what each key means. Merge into the file Step 2e already
started; never overwrite its `openspec` key, only add the rest around it.

Two rules from that file are worth stating here too, because they are the
ones a run gets wrong: every field must be a real detected or user-confirmed
value (never a literal placeholder — ask rather than guess), and
`harnessVersion`/`toolchainVerifiedAt` are **not** written here. They are
claims about a finished run, and Step 8b writes them once it passes.

## Step 8b — prove the toolchain actually runs

Everything up to here has *detected* a toolchain. Nothing has *run* it. A
project whose script is called `type-check` rather than `typecheck` gets a
`.husky/pre-commit` that fails on every commit and a `Stop` hook that reports
"script not found" as if it were a type error — neither of which surfaces
during setup. An instruction to be careful is not a check; this step is the
check.

Runs in **both** first-install and upgrade mode, on a clean tree (if the tree
is dirty, ask the user to commit or stash first — a lint failure from their
own uncommitted work would be blamed on the harness).

**Read `references/toolchain-proof.md` now and follow it.** The four checks
it walks, in order:

1. **The keys exist** — `scripts.typecheck`, `scripts.lint`,
   `scripts.testCoverage` each name a real key in `package.json`. A mismatch
   is corrected in *both* the manifest and the `.husky/` hook that embeds it.
2. **Typecheck and lint pass** — both exit 0, or the harness would block
   every commit from the moment it is installed.
3. **The tests run and at least one passes** — read the count, not just the
   exit code; `--passWithNoTests` makes an empty run look green.
4. **Any of the three not satisfied → stop the whole `init-harness` run**,
   and leave `harnessVersion` and `toolchainVerifiedAt` unwritten so the next
   run re-attempts instead of skipping as already-current.

Only once all three pass does this step write `harnessVersion` and
`toolchainVerifiedAt`. That pair is the difference between "the harness found
these names" and "the harness ran these commands" — do not write either one
on any other path.

## Step 9 — create or append CLAUDE.md's harness pointer block

`.claude/docs/*.md` (Step 5) is **not** auto-loaded the way
`CLAUDE.md`/`AGENTS.md` is. Without a pointer from the root instruction file,
nothing in Step 5 is discoverable — and the auto-commit override
`opsx-apply-git` §3/§5.3 relies on is only recognized when it is referenced
from the project's CLAUDE.md. Skipping this step doesn't just lose
documentation; it silently withdraws that authorization.

**Read `references/claude-md-pointer-template.md` now and follow it** — it
holds the block to write and the create-vs-append rule. Never overwrite or
reorder existing content in a file that already exists, and keep the block
short: Gate 6 checks the root instruction file stays near 200 lines.

## Step 10 — report

In upgrade mode, report the shorter form Step 0 describes — version
transition, files created, files appended to, files left alone — not the
full first-install summary below, which mostly restates what the user
already has.

Either mode: state that the three scripts were run and passed (Step 8b),
naming them — this is the one thing in the report the user can't infer from
the file list, and it is the difference between "the harness found these
names" and "the harness ran these commands".

For a first-time install: summarize what was detected (framework, package manager, test runner),
confirm OpenSpec is initialized and say whether `openspec/config.yaml`
(Step 2f) got the user's domain description or only the technical half —
they can still add it later, and knowing it's missing is what prompts them
to. State the coverage threshold chosen, and
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
