# Forge detection, and the warning when it isn't GitHub

Read this from Step 1. `init-harness` needs to know, once, which code forge
a repository's `origin` points to — `opsx-apply-git`'s delivery step and
`archive-run.md`'s PR-state check both read the result from
`.claude/harness.json` instead of assuming GitHub the way they used to.

## Detecting it

```bash
origin_url="$(git remote get-url origin 2>/dev/null)"
```

No `origin` at all is not an error — it resolves the same as any other
non-GitHub address, below.

Match `$origin_url` against the `github.com` host, in whichever URL form
git produced (`https://github.com/...`, `git@github.com:...`,
`ssh://git@github.com/...`):

- Matches → `"github"`.
- Doesn't match, or `origin_url` is empty → `"other"`. Two values are
  enough: this harness's delivery step doesn't work on GitLab, Bitbucket, or
  Azure DevOps any differently from one another, so telling them apart would
  record a distinction nothing downstream reads.

Step 8 writes whichever value this step determined into the manifest's
`forge` key — see `manifest-schema.md`. This file only determines the
value; it doesn't write the manifest itself.

## The warning, when it resolves to `"other"`

Say this to the user, in one paragraph, right here at detection time — not
deferred to the final report: this repository's forge isn't GitHub, so the
step that opens a pull request won't work; everything else in this harness
works the same regardless of forge; open the pull request by hand when a
run finishes (it prints the branch, the target branch, and the PR body text
ready to paste). Setup does **not** stop here, and the repository is still
considered fully configured once the rest of this skill finishes — the only
thing it loses is that one step.
