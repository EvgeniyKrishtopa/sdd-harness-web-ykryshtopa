# A small task outside OpenSpec — a chore run

Referenced from `SKILL.md` §0 and from the project's
`.claude/docs/git-conventions.md` (0.12.0).

A chore run is a small task the human asks for that has no OpenSpec
change: a dependency bump, a config tweak, a copy fix, a one-file bug fix.
It goes through the same checks, log and PR shape as a normal run, without
`tasks.md`, groups, `PROGRESS.md` or archiving. A task that needs a
proposal (two or more layers, a new behaviour worth a spec) is not a chore:
say so and offer `opsx-propose-review` instead.

## 1. Branch

Pick a slug, kebab-case, a few words (`bump-zod`, `fix-footer-link`). A
slug that names a folder under `openspec/changes/` (archive included) is
taken: the log, the review trail and the `@<slug>` scenario tag key on
it — pick another. Cut `chore/<slug>` off the main branch's current tip,
found the same way as in `parent-branch.md`:

```bash
git fetch origin
main=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
  || git ls-remote --symref origin HEAD | awk '/^ref:/{sub("refs/heads/","",$2); print "origin/"$2; exit}')
base="${main#origin/}"
git checkout --no-track -b "chore/<slug>" "$main"
```

`<parent>` below is `$main` in every `git diff`/`git log`, and `$base` (no
`origin/`) wherever a branch name is meant: `gh pr create --base "$base"`,
the printed PR for `forge` `"other"`, §4 step 5. The human names another
branch → use it instead. No `origin` → stop and ask.

## 2. Do the task, check the UI, commit

Implement it with the usual guardrails (`command-hygiene.md`, and
`context7-lookup.md`'s trigger for a named library API). Behaviour changed →
add or update a test.

**Installing, adding or updating a package is the human's step.** The
project's `permissions.deny` forbids the agent every install command, on
purpose: a package runs its own scripts on install. Stop and warn, in one
message: what the task needs installed, why the agent doesn't run it, and
the exact command to run in the prompt, e.g.
`! npm install zod@4.1.0` (the project's package manager, the version the
task names). Wait for the human; once they say it ran, check the lockfile
changed and go on — typecheck, lint, tests. Never route around the deny: no
other package manager, no `npm update`, no `npx`, no editing the lockfile
by hand. The human declines → stop the chore run and say so. Once the project's typecheck, lint and tests pass:

1. **`web-qa` (Gate 3), before the commit**, as for a change's last group —
   only when the diff touches user-facing UI, its fixes folding into the
   commit. Otherwise its line is `skipped`, `UI not touched`.
2. **Commit**, with a Conventional Commits subject whose type fits the work
   (`chore`, `fix`, `refactor`). The project's `git-conventions.md` must
   name the chore run in its commit override (0.12.0). A project set up
   earlier may not have that line yet: then ask before this commit, and
   suggest `init-harness` to bring the file up to date.

## 3. Checks — the same rules for skipping

Run `SKILL.md` §4 against the chore's diff as a one-group run that is also
the change's **last** run:

- §4 step 1's trivial-diff check decides whether `code-review` runs at all
  (`small change`), exactly as in any run — no other skip.
- Tell `code-review`: a chore run, the **final** run, no `tasks.md`, no
  test plan, no proposal. Its traceability and test-plan checks then say
  "not available" instead of guessing.
- PLAUSIBLE findings go to the human as in Case B (`plausible-fix.md`),
  since the human asked for this task and is there. No "Judgement-heavy"
  marker in the PR body.
- §4 step 3: `harness-review`'s precondition is always checked (a chore has
  no "last group" to wait for).
- §4 step 3a: the replay runs as a last run — the affected scenarios over
  the chore's diff, `--change "<slug>"` (`e2e-replay.md`). A dependency
  bump is exactly what can break an old flow.
- `architecture-review` and `spec-review` never run: there is no change to
  review.

Every log line this run writes uses `change: "<slug>"` and `group: "-"`, in
this branch's own file (`.claude/harness-log/chore--<slug>.jsonl`). The
pre-push hook, its note and its log line work as in any run
(`pre-push-note.md`).

## 4. PR

Push, then commit and push the log (`log-findings.md`, "Committing the
log"), then open the PR into `$base` (or print it, for `forge` `"other"`).
The body has the same two sections as any run:

- **What changed and why** — 3-5 plain sentences, as in `SKILL.md` §4
  step 6.1.
- **Review trail** — the four parts of `log-findings.md`, with:
  - **Change**: `No OpenSpec change — chore run <slug>.`
  - **Checks**: `architecture-review` and `spec-review` each say
    `not run: no OpenSpec change`; the other four as usual.
  - **Findings**: as usual.
  - **Deferred**: `None — no OpenSpec change.`

Leave the PR open; the human owns the merge. Nothing to archive, and
`PROGRESS.md` is not touched.
