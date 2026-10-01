# Command hygiene

Read this before the run's first Bash call. Each rule below comes from a
real autonomous run that stalled on a manual prompt, or reported success
for something that hadn't happened. The rules don't make the hooks correct;
the hooks have to be correct on their own. What the rules remove is the
prompts and the hidden failures.

## No `cd <repo> &&` prefix

The session already runs in the repo root, so use relative paths. Claude
Code stops every compound command that pairs `cd` with a write
(`cd /path/to/repo && mkdir -p x && printf ... > x/y`) and asks for manual
approval before any allow rule is checked. So an autonomous run waits on a
human for a `cd` that did nothing.

## Probes go in the scratchpad

A one-off test, script or output file you need for a moment goes in the
session scratchpad (or `mktemp`), not in the repo. Inside the repo it gets
picked up by the test runner, lint, coverage and `git add`, and someone has
to remember to delete it. If the test runner only finds tests inside the
repo, the probe is really a test: write it where the group's tests go, or
delete it before the group's commit. `git status -s` must not show it.

## Edit files with Edit and Write, not with scripts

Change `tasks.md`, `design.md`, `PROGRESS.md`, a PR-body file or any other
file with the Edit or Write tool. Never use `python3 - <<'EOF'`, `sed -i`,
`perl -pi` or `cat > file <<EOF`. Three reasons:

- Each script needs a manual prompt. Running arbitrary code is deliberately
  not allow-listed: `Bash(python3:*)` could write any file and would route
  around the deny list.
- A script edit shows no diff a human can review.
- A script fails silently. `s.replace(old, new)` with an `old` that isn't
  in the file changes nothing, and the script still prints "updated". Edit
  fails loudly when its anchor text isn't there.

Bash is for commands that aren't file edits: the project's checks, git,
`gh`, and the `jq ... >> .claude/harness-log.jsonl` append this skill
documents.

## Never pipe `git push`

Run `git push` on its own. Not `git push 2>&1 | tail -1`, not
`git push -q 2>&1 | grep -E "error"`. A pipeline's exit status is the last
command's, so when pre-push fails (tests, coverage, the dependency audit),
the pipeline still succeeds. The push silently doesn't happen, and the
`gh pr create` after it fails with no visible cause. Chain the next step
with `&&`, not a newline, or check `$?` before going on. The same goes for
any command whose failure matters, such as the project's own test run.

Write "pre-push passed" in a PR body only after `git push` has returned 0.
A body drafted before the push must not claim it.

## Several short calls, not one long chain

Prefer several short Bash calls to one `&&` chain that mixes `$(...)`,
heredocs and git commands. When a long chain fails in the middle, it is
hard to see which part failed. Long chains also make the hooks' `if`
filters match loosely, and each extra prompt costs a human interruption.
