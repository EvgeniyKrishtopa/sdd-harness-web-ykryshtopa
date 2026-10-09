# §1 — which branch is the parent

Read this when §1 step 1 starts on a branch that looks like a leftover
group branch, and for §1 step 3 on every run. Both decide where the next
group is cut and where its PR goes, so both act on facts git or the forge
can show, never on a guess.

## A leftover group branch (§1 step 1)

A batch, group or archive branch this skill cut earlier. Check its PR
before asking anything. Read `forge` from `.claude/harness.json`; if the
file is missing, stop the way §1 step 2 says.

`forge` is `"github"` or absent → `gh pr view --json state,baseRefName`
on the branch:

- `MERGED` → `git checkout <baseRefName>` — that is the parent — and say so
  in one line: `Branch <group> is merged into <baseRefName>; switched to
  <baseRefName>.` Then go on. An archive branch means the change is already
  archived: report that and stop. A change with no pending tasks left goes
  to §5 with this PR as the run's PR.
- Any other state, no PR for the branch, or `forge` `"other"` → stop and
  ask which branch is the real parent.

Switch only on `MERGED`: the PR's own base is the one fact that says where
the group's work went, and a wrong guess sends the next run to the wrong
branch.

## A parent already in the main branch (§1 step 3)

A parent merged into main and left behind keeps old code: a group cut from
it builds on that. Skip this when the parent is the main branch itself.

```bash
git fetch origin
main=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null \
  || git ls-remote --symref origin HEAD | awk '/^ref:/{sub("refs/heads/","",$2); print "origin/"$2; exit}')
git merge-base --is-ancestor <parent> "$main" \
  && { ! git rev-parse -q --verify "origin/<parent>" >/dev/null \
       || git merge-base --is-ancestor "origin/<parent>" "$main"; } \
  && git rev-list --count "<parent>..$main"
```

`$main` empty (no `origin`) or the check prints nothing or `0` → nothing to
do; go on. A number above 0 → the parent, local and on `origin`, is all in
`$main`, and `$main` has moved on:

- `PROGRESS.md`'s `## PR target` has a line for this parent → follow it,
  no question.
- Otherwise ask (`AskUserQuestion`): send this change's group and archive
  PRs into the main branch (recommended), or keep the parent. Record the
  answer with the script, never by hand:
  ```bash
  node "${CLAUDE_PLUGIN_ROOT}/skills/opsx-apply-git/scripts/progress.mjs" pr-target \
    --parent "<parent>" --target "<chosen branch>" --date "$(date -u +%Y-%m-%d)"
  ```
- No answer → stop. Never cut a group from this parent without one.

Main chosen → `git checkout <main, without origin/>`. From here it is the
parent for the rest of this flow: syncing, the group branch, the run's PR,
the archive PR.

The check sees a parent merged with a merge commit or fast-forward. A parent
squash- or rebase-merged into main has new commit hashes there, so git
cannot tell it is merged and the check stays silent: the run goes on from
the parent, as before 0.12.0.
