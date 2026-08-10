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
| `openspec/config.yaml` | Step 2f | add missing `context`/`rules` keys; never touch `schema`, never replace existing content without asking |
| `.husky/pre-commit`, `.husky/pre-push` | Step 3 | append missing checks, never clobber |
| `.claude/docs/git-conventions.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/docs/review-gates.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/docs/laziness-ladder.md` | Step 5 | create if absent; diff and ask if it differs |
| `.claude/settings.json` (`permissions` only) | Step 6 | merge and de-duplicate entries |
| `.claudeignore` | Step 7 | append missing lines |
| `.claude/harness.json` | Steps 2e, 8, 8b | merge keys (including `webQaScenariosDir`, added 0.4.0, and `disabledRules`, `models.clarify`, `models.deep`, and `sizeRouting`, all added 0.5.0 — see Step 8); never drop keys already there |
| `CLAUDE.md` / `AGENTS.md` pointer block | Step 9 | append missing lines only |
| `CONTEXT.md` | Step 5 | create if absent, starting empty (heading only, no entries); never diffed or touched afterwards |
| `PROGRESS.md` | Step 5 | create if absent; afterwards only `opsx-apply-git` regenerates it at run boundaries, never freeform-edited |
| `.gitattributes` (`PROGRESS.md merge=union`) | Step 5 | append the line if missing; never touch other lines |
| `docs/decisions/NNNN-*.md` | `opsx-apply-git` §3 Case A or B, or `record-decision`, on demand | one new file per decision; never edited after acceptance — superseded by a new file instead (0.5.0: Case A and `record-decision` both added as writers alongside Case B) |

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
