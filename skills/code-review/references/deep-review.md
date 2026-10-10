# The deep review — when it runs, and why on that condition

`code-reviewer` has no security rules at all, and reads architecture only as
local reuse and simplification within the diff's neighbourhood. On a diff
that carries real risk that is not enough, so a second reviewer —
`deep-reviewer` (`agents/deep-reviewer.md`, rule codes `DR-01`…`DR-12`) —
runs on top of it.

It is a full extra delegation, usually on a larger model, so it only runs
when a deterministic shell check says the diff touches something worth the
run. Never "ask the model whether this looks risky": that spends exactly what
this check exists to save.

## The prefilter (0 tokens)

```bash
range="<parent>..HEAD"   # the same range Action step 1 resolves
path_re='auth|login|logout|session|passwo?rd|token|permission|role|polic|payment|billing|checkout|invoice|migrat|schema|\.env|secret|credential|upload|\.github/(workflows|actions)/|\.gitlab-ci\.ya?ml$|\.circleci/|(^|/)dockerfile[^/]*$|(^|/)vercel\.json$|(^|/)netlify\.toml$'
content_re='localStorage|sessionStorage|document\.cookie|dangerouslySetInnerHTML|innerHTML|eval\(|new Function\(|child_process|execSync|jwt|bcrypt|argon2|createHmac|randomBytes|cors\(|csrf|multipart|\.raw\(|SELECT .* FROM|INSERT INTO|DELETE FROM|permissions:|secrets\.|pull_request_target|workflow_run|GITHUB_TOKEN|id-token: *write'

# Documents and tests execute nothing in production: no signal from them.
skip_re='^(docs|openspec)/|\.(md|markdown)$|^(src/)?(tests?|e2e)/|(^|/)(__tests__|__mocks__)/|\.(test|spec)\.[cm]?[jt]sx?$'

paths=$(git diff --name-only "$range")
if [ -z "$paths" ]; then
  echo "prefilter unavailable: git diff --name-only $range listed no files"
else
  paths=$(printf '%s\n' "$paths" | grep -viE "$skip_re")
  signal="path"
  hits=$(printf '%s\n' "$paths" | grep -iE "$path_re")
  if [ -z "$hits" ]; then
    signal="content"
    hits=$(printf '%s\n' "$paths" | grep . | while IFS= read -r f; do
      git diff "$range" -- "$f" | grep '^+' | grep -v '^+++' \
        | grep -qiE "$content_re" && printf '%s\n' "$f"
    done)
  fi
  [ -z "$hits" ] && echo "risk=none" \
    || { echo "risk=$signal"; printf '%s\n' "$hits"; }
fi
```

It **prints** its result rather than leaving it in a shell variable. Each
`Bash` call is its own process, so a `$risk` left unset in the environment
would be gone before anything could read it — the sibling prefilter in
`traceability-prefilter.md` echoes all three of its outcomes for the same
reason. It prints the matching **filenames** too, not just the verdict:
those are what gets handed to the agent.

Path signals are checked before content signals. The content grep excludes
`+++` header lines before matching, so a signal word appearing only in a
*filename* cannot masquerade as added content (without that `grep -v`, a
comment tweak in `jwt-utils.ts` reports `risk=content`), and it looks only at
added lines — a risky pattern this diff *removes* is not worth a review.

Neither signal looks at documents or tests (`skip_re`, 0.12.0): Markdown
anywhere, everything under `docs/` and `openspec/`, and test files —
`*.test.*` and `*.spec.*` anywhere, anything inside `__tests__/` or
`__mocks__/` anywhere, and anything inside `tests/`, `test/` or `e2e/` only
at the project root or directly under `src/`. A README that explains
`GITHUB_TOKEN`, a spec for a login change, or a test of the session cookie
executes nothing in production, and these words are exactly what such files
mention. Before 0.12.0 path signals still applied to them, so a change of
only documents and tests about sign-in spent a deep review on the larger
model for nothing. A risky change always comes with the source file that
does it, and that one is checked.

A `test` folder deeper down is not counted as tests: there it is often
working code — an API route (`src/app/api/test/route.ts`) or a CI action
(`.github/actions/test/action.yml`). Matching it at any depth dropped both
out of the check. `.mdx` is scanned everywhere except under `docs/` and
`openspec/`: it compiles to components and can carry real JSX.

## CI/CD signals (added 0.10.4)

A workflow file runs with the repository's token and secrets, so it is
production configuration. Before 0.10.4 a diff that added
`.github/workflows/ci.yml` with `permissions:` and a `pull_request` trigger
logged "no risk signals". Each signal below is a file most runs never touch,
or a word that appears almost only in such files:

| Signal | Why |
|---|---|
| `.github/workflows/`, `.github/actions/` | Workflows and local actions run with the repo token and secrets. |
| `.gitlab-ci.yml`, `.circleci/` | The same for GitLab and CircleCI. |
| `Dockerfile*` | Base image, runtime user, and build-time secrets of what ships. |
| `vercel.json`, `netlify.toml` | Production headers, redirects, rewrites, and function config. |
| `permissions:` | Token scope of a workflow or job. |
| `secrets.` | A secret read into a step — `${{ secrets.X }}`. |
| `pull_request_target`, `workflow_run` | Triggers that run with write access and secrets on fork-supplied input. |
| `GITHUB_TOKEN` | The token used directly, including from a script outside `.github/`. |
| `id-token: write` | OIDC — the job can obtain cloud credentials. |

Not added: `on: push`, `uses:`, `runs-on:`. They appear in every workflow
and add nothing the path signal does not already catch.

## Reading the three outcomes

- **`risk=none`** → do not spawn `deep-reviewer`; log the skip and carry on
  with Gate 4/5 exactly as before. This is the common case.
- **`risk=path` / `risk=content` plus filenames** → run it. Tell the agent
  which signal fired and which files matched: that is the only clue it has
  about why it was spawned, and it uses it to decide what to read deeply
  beyond the diff hunks.
- **`prefilter unavailable`** → **fail open**: spawn `deep-reviewer` on the
  whole diff and say in the report that the prefilter could not run. A bad
  revision range produces an empty file list, which is byte-identical to "no
  risk found" — and quietly skipping is how the only security review in this
  plugin disappears without anyone noticing. Never collapse this outcome
  into `risk=none`; it is the same silent-collapse failure
  `traceability-prefilter.md` guards against for coverage.

Both regexes are deliberately broad on recall and loose on precision: a
false fire costs one delegation, a miss costs the only security review this
plugin has. If a project finds a specific rule consistently unhelpful it
switches that rule off by code in `disabledRules` — the prefilter itself is
not the tuning surface.

## What the signals do and do not cover

The signals are security-shaped by design. The architecture rules
(`DR-07`…`DR-11`) therefore ride along on a security signal rather than
having triggers of their own: a diff that touches auth or billing gets its
boundaries and layering read as well, and a diff that only reshuffles
components does not.

That is a deliberate trade, not an oversight. Architecture-shaped path
signals (`components/`, `hooks/`, `store/`, `services/`) match nearly every
diff in a React codebase, which would turn a rare deep pass into a permanent
second reviewer on every run — exactly the cost this whole design refuses.
Gate 1 still reviews architecture on every change's `design.md`; what rides
on the risk signal is the second read, against the code as built.

## Why it is not tied to the change's route

The obvious cheaper design is "short route → never run it." Rejected, on two
grounds:

- Item 11 of this version wrote its own rule down: the short route skips
  **documents**, never a check on the result. This is a check on the result.
- The route is assigned by an estimate made in `opsx-propose-review`, before
  any code exists. One low estimate would then silently switch off the only
  security review in the plugin — and silently, because a skipped gate that
  was skipped "correctly" looks exactly like one that was never needed.

The saving would also be near zero in practice: a diff that trips the risk
prefilter is a diff touching a schema, a contract, or auth, and item 11 sends
exactly those down the full route anyway.

The risk prefilter is the single condition.

## Why a second agent rather than more rules in `code-reviewer`

Three reasons, in order of weight:

1. **It must be skippable.** Rules added to `code-reviewer` run on every
   diff, including the button-label edit. A separate agent is the only way to
   make a deep pass conditional at zero cost when it does not apply.
2. **Different verification bar.** `code-reviewer` confirms a finding by
   pointing at a broken behaviour. A security finding is confirmed by tracing
   an input someone controls to the damage — the code usually works exactly
   as written. Mixing the two bars in one agent blurs both.
3. **Different model.** The deep pass is worth a larger model precisely
   because it runs rarely; `code-reviewer` is worth a cheaper one precisely
   because it runs always. One agent cannot be both.
