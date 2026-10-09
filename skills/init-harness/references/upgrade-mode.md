# Upgrade mode, and the file inventory this skill owns

Read this when Step 0 lands on branch 3 (UPGRADE MODE), and whenever you
need the inventory of files this skill writes into a target repository.

Gate 6 (`harness-review`) reads the inventory too, when it checks for drift.

## The file inventory this skill owns

Upgrade mode walks this list. Every future release that teaches this skill
to write a new file into the target repo **must add it here in the same
commit** — a file that exists only in the first-time path reaches new
repositories and no one else, which is the whole failure this inventory
exists to prevent.

| Path | Written by | Merge rule |
| --- | --- | --- |
| `openspec/` workspace | Step 2b | created by `openspec init`; never re-initialized over existing work |
| `openspec/config.yaml` | Step 2f | add missing `context`/`rules` keys **and any individual rule missing from a `rules.*` key that already exists** — a repo configured by an earlier version has `rules.proposal`, so "the key is there" is not "the rules are there" (0.5.0's Given/When/Then acceptance-criterion rule reaches configured repos only this way); never touch `schema`, never replace existing content without asking |
| `.husky/pre-commit`, `.husky/pre-push` | Step 3 | append missing checks, never clobber. `.husky/pre-push` (0.11.0, 0.12.0): see "The 0.11.0 pre-push" and "The 0.12.0 log-only check" below |
| `scripts/deps-audit.mjs`, `scripts/audit-allowlist.json` (`references/deps-audit.md`) | Step 3, on a "yes" only (0.12.0) | copied only when `depsAudit` is `"script"`; an existing script or allowlist is never overwritten — the allowlist's entries are the project's decisions. See "The 0.12.0 audit script" below |
| `.gitignore` (`.claude/.last-pre-push.json`) | Step 3 | append the line if missing, only when `.husky/pre-push` writes the note (0.11.0) |
| `.claude/docs/git-conventions.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/docs/review-gates.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/docs/laziness-ladder.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/settings.json` (`permissions` only) | Step 6 | merge and de-duplicate entries. This includes the test-runner line `Bash(npx {{TEST_RUNNER_CMD}}:*)` (0.10.2), substituted from the manifest's `testRunner`; a runner other than vitest/jest gets no line. `Bash(npx playwright test:*)` (0.11.0) is merged in the same way when `@playwright/test` is in `devDependencies`, and never as `npx playwright:*` |
| `.claudeignore` | Step 7 | append missing lines |
| `playwright.config.*` | Step 1b, on a "yes" only | created only when absent and the user accepts it (`references/test-layers.md`); an existing one is never edited — its gaps are listed in the report |
| `package.json` `test:integration` script, `vitest.integration.config.ts` with `tests/integration/global-setup.ts` (`references/local-stack-profile.md`; or a second Jest config), the main test config's exclude | Step 1b, on a "yes" only | created only when the project has a local service, no integration script, and the user accepts (`references/test-layers.md`); the main config's change is shown as a diff first |
| `scripts/qa-preflight.mjs` and the `package.json` `qa:preflight` script (`references/local-stack-profile.md` section 3) | Step 1b, on a "yes" only | drafted with probes that name variables, never values, and written only on a second "yes", when `tests.e2e` has no `preflight` yet; an existing file is never overwritten (`references/test-layers.md`) |
| *(none — printed, never written)* CI job template | Step 10, on a "yes" only | printed into the report; no file is written, in `.github/workflows/` or anywhere else |
| *(none — printed, never written)* scheduled audit job template (`references/deps-audit.md`) | Step 10, on a "yes" only (0.12.0) | printed into the report; no file is written, in `.github/workflows/` or anywhere else |
| `.claude/harness.json` | Steps 2e, 8, 8b | merge keys (`disabledRules`, `models.clarify`, `models.deep`, and `sizeRouting`, all added 0.5.0; `forge`, added 0.6.0; `scaffold`, added 0.7.0; `makerChecker` with `models.testAuthor`, added 0.9.0; `designSystem`, added 0.10.0, always merged in as `{"enabled": false}` regardless of what else the upgrade found — see Step 8; `depsAudit`, added 0.12.0 — written only from the user's answer; the optional `tests` block, added 0.11.0 — a `tests.integration` without `envCommand`/`mailCatcherUrl` gets them offered in the same one question as a first install, never written unasked); `models.*` full names become short names (0.12.0, see "The 0.12.0 model names" below); never drop keys already there, with one exception: the two keys `tests` replaced are moved into it and removed (see "Moving the pre-0.11.0 test keys" below). `tests.integration` is not merged in blindly: look for the script the same way a first install does (`references/stack-detection.md`), and when the project has none, write no key — an upgrade must not invent one |
| `CLAUDE.md` / `AGENTS.md` pointer block | Step 9 | append missing lines only, inside the existing `## Harness (...)` block. The two-line Shell bullet (0.10.2) is skipped when the file already says the same thing in the user's own words anywhere: a `## Shell` section or any line telling the agent not to prefix commands with `cd` into the repo counts. Two versions of one rule are a maintenance problem, and the user's version is the one they chose |
| `CONTEXT.md` | Step 5 | create if absent, starting empty (heading only, no entries); never diffed or touched afterwards |
| `PROGRESS.md` | Step 5 | create if absent; afterwards only `opsx-apply-git` regenerates it at run boundaries, through `scripts/progress.mjs`, never freeform-edited. Local since 0.12.0: if git tracks it, `git rm --cached PROGRESS.md` (the file stays on disk) and tell the user to commit that with the upgrade |
| `.gitignore` (`PROGRESS.md`) | Step 5 | append the line if missing (0.12.0) |
| `.gitignore` (`.playwright-mcp/`) | Step 5 | append the line if missing (0.12.0) |
| `.gitattributes` (`PROGRESS.md merge=union`, `.claude/harness-log.jsonl merge=union`) | Step 5 | no longer written (0.12.0): **remove** each of these two lines if present, and nothing else — the file itself stays, even if that leaves it empty. The old `.claude/harness-log.jsonl` itself is never moved or deleted — `harness-stats` still reads it |
| `docs/decisions/NNNN-*.md` | `opsx-apply-git` §3 Case A or B, or `record-decision`, on demand | one new file per decision; never edited after acceptance — superseded by a new file instead (0.5.0: Case A and `record-decision` both added as writers alongside Case B) |
| `docs/deferred.md` | `opsx-apply-git` §3 and §5, on demand | never created here, on first install or on upgrade: `opsx-apply-git` creates it the first time a group leaves something blocked, skipped or obsolete, so a project with nothing deferred has no empty file. Upgrade only appends the pointer bullet (0.10.5) |
| *(none — reads only, writes nothing)* linter ruleset check | Step 8b | recommendation, not a merge target: compares the project's linter config against `references/linter-ruleset.md`, reported every upgrade run, never installs or edits config (0.6.0) |

## Moving the pre-0.11.0 test keys

0.11.0 moved two keys into the `tests` block
(`references/manifest-schema.md`). One value in two places is two sources
of truth, so an upgrade moves each one and deletes the old key:

1. `scripts.testIntegration` present → write its value to
   `tests.integration.script`, then remove `scripts.testIntegration`.
2. `webQaScenariosDir` present → write its value to `tests.e2e.dir`, write
   `"replayBeforePush": false` next to it, then remove `webQaScenariosDir`.
   The `false` is required: the block existing would otherwise turn the
   replay before push on by default, and turning it on is the user's
   decision, not the upgrade's. Write no other `tests.e2e` field.
3. `tests` already holds a value for the same field and it differs from the
   old key → show both and ask which one to keep. Never pick one, and never
   delete the old key before the user answers.
4. Report one line per key moved, e.g. `webQaScenariosDir →
   tests.e2e.dir (tests/web-qa-scenarios)`. Moving `webQaScenariosDir` adds
   one more line: `e2e replay before push is off; to turn it on, set
   tests.e2e.replayBeforePush: true`.

A manifest with neither old key gets nothing from this section.

## The 0.11.0 pre-push

0.11.0 changed `.husky/pre-push` from one chain into two parts
(`references/git-hooks.md` step 4): a block that lets a log-only push
through untested, and — with an integration script — a short script that
checks the services and leaves the note `opsx-apply-git` logs from.

1. The hook is exactly a chain this skill wrote before — `<pm>
   test:coverage && <audit>`, or with `<pm> <integration script> &&` in the
   middle, nothing else but blank lines and comments → show the new hook as
   a diff and replace it on the user's yes.
2. Anything else (a human edited it) → don't guess where the new parts go.
   Print both blocks, filled in, and ask the user to merge them by hand;
   one report line says so.

## The 0.12.0 log-only check

0.12.0 moved the harness log into one file per branch, so the first block
of `.husky/pre-push` (`references/git-hooks.md` step 4) matches a new
pattern. Find the line that still names the old file only:

```sh
grep -n "grep -vxF .claude/harness-log.jsonl" .husky/pre-push
```

1. Found, and the block around it is the one this skill wrote → show the
   one-line change as a diff (`grep -vxF .claude/harness-log.jsonl` →
   `grep -vxE '\.claude/harness-log(\.jsonl|/[^/]+\.jsonl)'`, and the
   comment line above the loop) and apply it on the user's yes.
2. Not found and no `only_log` block at all → the hook predates 0.11.0;
   "The 0.11.0 pre-push" above already brings in the new block.
3. Anything else → print the new block and ask the user to merge it by
   hand; one report line says so.

Skipping this costs time, not safety: the old pattern doesn't recognise a
push of the new log files as log-only, so that push runs every test.

## The 0.12.0 audit script

`.claude/harness.json` has no `depsAudit` → ask `references/deps-audit.md`'s
question once and record the answer, whichever it is.

1. `"plain"` → nothing else changes.
2. `"script"` → copy the two files as that reference says. Then find the
   plain audit command in `.husky/pre-push`: found exactly once → show the
   one-line change to the script call as a diff and apply it on the user's
   yes. Not found, or found more than once → print the script call and ask
   the user to put it in by hand; one report line says so.

Ask the regular-audit question from the same reference in the same run,
whatever the answer above: the printed job works with either hook.

## The 0.12.0 model names

Before 0.12.0, `models.*` held full names (`claude-sonnet-5`), which the
`Agent` tool's `model` parameter doesn't accept. Check every `models.*`
value against `references/manifest-schema.md`'s `models` entry:

1. A short name (`sonnet`, `opus`, `haiku`, `fable`) → keep it.
2. A full name in that entry's table → replace it with its short name; one
   report line lists each key changed, `old → new`.
3. Anything else → stop the upgrade with `models.<key> is "<value>": use
   sonnet, opus, haiku or fable`, before writing anything, and leave
   `harnessVersion` as it is. Guessing a family from an unknown name could
   send a review to a model the user never chose.

## How upgrade mode runs

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
- **Then write `harnessVersion`** (Step 8b writes it, not Step 8), and only
  then, gated on exactly what Step 8b itself gates on: the three toolchain
  checks passing, plus Step 2c's workflow check earlier in the run. If either
  of those stopped the whole run, leave `harnessVersion` at its old value —
  a version number claiming an upgrade that didn't finish is worse than no
  version number, since the next run would skip via branch 2 above instead
  of re-attempting it. A user **declining a single file's template diff**
  (Step 5) is a different, narrower kind of outcome: only that one file is
  left as-is, the run continues, and it does not by itself withhold
  `harnessVersion` — the repo choosing to keep a customized doc over the
  newest template text is still fully configured for this plugin version.
- **Report what changed** (Step 10): the version transition
  (`<old or "unversioned"> → <new>`), each file created, each file appended
  to, and each file left alone. "Already up to date" is a real and common
  outcome — say it plainly rather than implying work happened.

Upgrade mode is the *only* way a repo picks up a new release's files. Do not
add automatic migration to `SessionStart` or any other hook: writing into the
user's repository without them asking is something this harness does nowhere
else. Version drift is *detected* automatically (Gate 6, checklist item 6)
and *fixed* on command.
