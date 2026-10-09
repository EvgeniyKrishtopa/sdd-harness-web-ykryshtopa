# A small task outside OpenSpec — a chore run

Referenced from `SKILL.md` "Exceptions" and from the project's
`.claude/docs/git-conventions.md` (0.12.0).

A chore run is a small task the human asks for that has no OpenSpec
change: a dependency bump, a config tweak, a copy fix, a one-file bug fix.
It goes through the same checks, log and PR shape as a normal run, without
`tasks.md`, groups, `PROGRESS.md` or archiving. A task that needs a
proposal (two or more layers, a new behaviour worth a spec) is not a chore:
say so and offer `opsx-propose-review` instead.

## 1. Branch

Pick a slug, kebab-case, a few words (`bump-zod`, `fix-footer-link`). Cut
`chore/<slug>` off the main branch's current tip, found the same way as in
`parent-branch.md`:

```bash
git fetch origin
main=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
  || git ls-remote --symref origin HEAD | awk '/^ref:/{sub("refs/heads/","",$2); print "origin/"$2; exit}')
git checkout -b "chore/<slug>" "$main"
```

The PR goes into that main branch (`<parent>` below), unless the human
names another branch. No `origin` → stop and ask.

## 2. Do the task and commit

Implement it with the usual guardrails (`command-hygiene.md`, and
`context7-lookup.md`'s trigger for a named library API). Behaviour changed →
add or update a test. Once the project's typecheck, lint and tests pass,
commit with a Conventional Commits subject whose type fits the work
(`chore`, `fix`, `refactor`) — the commit override in git-conventions.md
covers the end of a chore run the same way it covers a group.

## 3. Checks — the same rules for skipping

Run §4 of `SKILL.md` against `git diff <parent>..HEAD`, as a Case B run of
one group, with these differences:

- `web-qa` (Gate 3) only when the diff touches user-facing UI, as for a
  last group; otherwise its line is `skipped`, `UI not touched`.
- `code-review` only for a noticeable source change. §4 step 1's
  trivial-diff check skips it as usual (`small change`). A diff that
  touches no source or test file at all (docs, config, lockfile only) skips
  it too, with all three lines `skipped`, `docs only` — written by hand in
  step 1's shape.
- `harness-review` — §4 step 3's precondition, unchanged.
- `architecture-review` and `spec-review` never run: there is no change to
  review.

Every log line this run writes uses `change: "<slug>"` and `group: "-"`, in
this branch's own file (`.claude/harness-log/chore--<slug>.jsonl`). The
pre-push hook, its note and its log line work as in any run
(`pre-push-note.md`).

## 4. PR

Push, then commit and push the log (`log-findings.md`, "Committing the
log"), then open the PR into `<parent>` (or print it, for `forge`
`"other"`). The body has the same two sections as any run:

- **What changed and why** — 2-4 plain sentences.
- **Review trail** — the four parts of `log-findings.md`, with:
  - **Change**: `No OpenSpec change — chore run <slug>.`
  - **Checks**: `architecture-review` and `spec-review` each say
    `not run: no OpenSpec change`; the other four as usual.
  - **Findings**: as usual.
  - **Deferred**: `None — no OpenSpec change.`

Leave the PR open; the human owns the merge. Nothing to archive, and
`PROGRESS.md` is not touched.
