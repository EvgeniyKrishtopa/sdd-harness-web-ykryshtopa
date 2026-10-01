# Intentional-red CI probes

Read this before a task whose acceptance criterion is a failure on the
remote: "CI goes red on a lint warning", "branch protection blocks the
merge", "the required check fails without tests". Such a task has to push
code that the local pre-commit and pre-push hooks refuse. Without a
sanctioned path, agents invent one: the first probe PR into a feature
branch was opened as a normal, mergeable PR, and cleanup depended on the
agent remembering.

## 1. Ask once, before the first probe push

Before anything leaves the machine, ask the human once with
`AskUserQuestion`. Name the throwaway branch, the branch under test, what
will be pushed (the deliberately failing change, in one line), and how it
gets there (see step 3). One approval covers every probe push of this task.
A probe is outward-facing and bypasses every local hook, so a human sees it
before it happens, not in the PR list afterwards. The `gh api` guard in this
plugin's hooks asks too; that ask confirms the call, this one confirms the
plan.

## 2. A throwaway branch off the branch under test

Create the branch from the branch the probe tests, named
`chore/<what-it-probes>-throwaway`, for example
`chore/lint-gate-throwaway`. The suffix tells anyone reading the branch
list that it is meant to be deleted.

## 3. Getting failing code onto the remote

Commit through the GitHub API (`gh api repos/<owner>/<repo>/git/blobs`,
`.../git/trees`, `.../git/commits`, then `.../git/refs` to create the
branch or `-X PATCH .../git/refs/heads/<branch>` to move it). This is the
documented route. `git commit --no-verify` and `git push --no-verify` stay
forbidden by `git-conventions.md`.

That is not a contradiction. `--no-verify` is forbidden because it ships
code past a failure that should have stopped it. Here the failure is the
expected result: the task is to prove the remote catches it. The API route
also never touches the local branch, so nothing failing lands in the run's
own history, and the human has approved it twice (step 1 and the hook's
ask).

## 4. Draft or normal PR

- **The probe checks CI results** (a job goes red, a required check
  fails): open the PR with `gh pr create --draft`. A draft runs CI the same
  way and can't be merged by accident.
- **The probe checks merge blocking** (branch protection, rulesets,
  required reviews): open a normal PR. A draft is unmergeable whatever the
  ruleset says, so it would hide whether the ruleset blocked the merge.
  Check the block with `gh pr view <n> --json mergeStateStatus` rather than
  by trying to merge.

## 5. Never merge, and clean up before calling it done

Never merge a probe PR. The task is not done until the PR is closed and the
branch is deleted, and both are verified:

```bash
gh pr close <n> --delete-branch
gh pr view <n> --json state --jq .state         # must print CLOSED
git ls-remote --heads origin <throwaway-branch> # must print nothing
```

Record the PR number and the observed result (which check failed, or that
the merge was blocked) in the task's commit message. That record is the
evidence the probe passed, once the PR itself is gone.
