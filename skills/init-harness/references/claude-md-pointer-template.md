# Step 9 — the CLAUDE.md / AGENTS.md pointer block

## Why this block is required, not cosmetic

`.claude/docs/*.md` (Step 5) is **not** loaded into context automatically the
way `CLAUDE.md`/`AGENTS.md` is. Without a pointer from the root instruction
file, no session ever reads `git-conventions.md` or `review-gates.md` unless
`opsx-apply-git` happens to read them itself — and more importantly, this
user's global instructions only recognize an auto-commit override ("commit
without being asked") when it is *referenced from the project's CLAUDE.md*.
`opsx-apply-git` §3 and §5.3 rely on `git-conventions.md` being exactly that
override, at group and archive boundaries. Without this step, that override
is undiscoverable, and a fresh session should fall back to asking before
every commit instead of trusting it.

## How to place it

1. Check for `CLAUDE.md`, or `AGENTS.md` if that's what this project already
   uses instead. If **neither exists**, create a minimal `CLAUDE.md`
   containing just the block below.
2. If **one already exists**, append the block to the end of it — never
   overwrite or reorder existing content, the same merge rule used for every
   other file this skill touches.
3. Prefer `@`-imports if the target Claude Code version supports them;
   otherwise plain links, one line of explanation each. Do not leave literal
   placeholder text.
4. Keep the block short. Gate 6 (`harness-review`) already checks that the
   root instruction file stays under roughly 200 lines — this step should
   never be the reason that budget gets exceeded.

## The block

```markdown
## Harness (sdd-harness-web-ykryshtopa)

- @.claude/docs/git-conventions.md — branch/commit conventions. This is
  also the documented authorization for `opsx-apply-git` to commit
  automatically at task-group and archive boundaries (its §3/§5.3) —
  without this reference, that override isn't discoverable and shouldn't
  be assumed.
- @.claude/docs/review-gates.md — the seven automated review gates and
  their order.
- @.claude/docs/laziness-ladder.md — priority order to check before
  writing new code; does not apply to trust-boundary validation,
  data loss, security, or accessibility.
- @CONTEXT.md — this project's glossary of domain terms. `spec-reviewer`
  checks every spec against it; without this reference it never loads into
  a session and the check has nothing to read.
- @.claude/harness.json — detected stack (framework, package manager,
  test runner, coverage threshold). Every skill and hook in this harness
  reads from here; do not re-detect any of it.
- PROGRESS.md — current change, status, and next steps as of the last
  stop. `SessionStart` already prints its in-progress/blocked line and
  Next steps section at the start of every session; read the file itself
  for anything beyond that digest (the Done list, clock-in/out history). Not
  `@`-imported — the hook already surfaces it, so importing it too would
  load the same content twice.
- docs/decisions/ — one ADR-format file per architectural decision that
  outlives a single change; see `docs/decisions/NNNN-*.md` if the
  directory exists yet. Not auto-loaded — read the relevant file when a
  past decision might be in play.
```
