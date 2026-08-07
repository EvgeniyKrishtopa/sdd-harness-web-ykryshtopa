---
name: dead-code-report
description: Finds unused files, exports, types, and dependencies with knip plus the project's own configured lint rules and a commented-out-code search, sorts findings into three confidence groups, and ends with a change-proposal draft -- never deletes anything itself. Use for "найди неиспользуемый код", "что можно удалить", "мёртвый код", or in English "find unused code", "what can be deleted", "dead code report". Run manually, roughly monthly, not on every task.
---

Find code nothing references anymore, and hand the result to the normal
change process. This is **not** one of this project's six review gates —
it runs on demand, not on every task, and it does not write to
`.claude/harness-log.jsonl` (see "Not a gate" below).

## Why this exists

The six automated gates only ever look at what a task *changed*. A function
that a task stopped calling — without touching the function itself — never
appears in any diff, so no gate ever sees it. It just accumulates. See
`harness-audit/v0.4.0-implemented/01-review-blind-spots.txt`, point 2, for the
full argument, and `05-design-rationale.txt`, decisions 1-4, for why this is
a command that reports rather than a seventh gate that deletes.

## First run vs. later runs

**Say this explicitly in the report, before anything else, on a project's
first-ever run of this command.** A first run is a baseline, not a deletion
list — it will surface scaffolding and libraries added ahead of code that
hasn't been written yet. The value here is in the *diff* between runs,
starting with the second one. Skipping this warning on run one is how a
noisy-looking first report kills the second run before it happens.

## Step 1 — Gather findings with tools, not the model

Run these three, in whatever order is convenient; none depends on another:

1. **`scripts/run-knip.sh [project-dir]`** — runs `npx knip --reporter json`
   without adding knip as a project dependency (installing packages is
   against this plugin's rules; `npx` fetches it on demand instead). Prints
   the JSON report to stdout on success.

   **If it exits non-zero**, knip could not produce a report at all (no
   network and nothing cached, `npx` missing, etc.) — read its stderr,
   report plainly that the knip portion of this run is unavailable and why,
   and continue with steps 2-3 anyway; don't treat this as a failure of the
   whole command. This must read as a clear, handled message, never a crash.

2. **The project's own configured lint command** (`package.json`'s `lint`
   script, or whatever `.claude/harness.json` records) — run it as-is. Knip
   does not see unreachable code *inside* a function body; whatever
   unreachable-code/no-unused-vars-style rules the project already has
   configured do. Read its output for findings of that shape; this command
   adds no new lint rules of its own.

3. **`scripts/find-commented-code.sh [project-dir]`** — a heuristic grep for
   `//` comments that look like disabled code rather than prose. Every hit
   goes to Group 2 directly (see Step 2) — a comment can never be verified
   "definitely dead" the way an unreferenced file can, so this script does
   not attempt to rank its own output.

## Step 2 — Classify into three groups

This is the one step that needs the model, not a tool.

- **Group 1, reliable** — a library nothing imports anywhere; a file with
  zero references that doesn't sit on a framework-reserved path (e.g. a
  Next.js route file, which is "used" by convention, not by import).
- **Group 2, needs a look** — referenced only by tests, Storybook, or
  config; every commented-out-code hit from step 1.3; anything you're not
  fully certain about.
- **Group 3, can't prove** — anything reachable only dynamically.

**Known false-positive shapes — check every candidate against this list
before Group 1, not after:** a computed/dynamic import or require path;
string-key lookup into an object (`components[name]`); i18n/translation
keys; feature flags; a reference that exists only in bundler/build config
(alias, `tsconfig.json` paths, test-runner setup files); a package's public
interface exposed via `package.json`'s `exports` field; a side-effect-only
import (polyfill, global stylesheet). A finding matching any of these starts
in Group 2 or 3, never Group 1. Full detail and examples:
`references/false-positives.md`.

## Step 3 — The safety net, before anything reaches Group 1

For every candidate Step 2 is about to place in Group 1, run:

```
scripts/verify-string-reference.sh <path-to-candidate-file> [project-dir]
```

This searches the whole project (excluding only `node_modules`, per the
plan, plus `.git` since that's history rather than the project as it stands
today) for the file's own name as plain text — including inside a string
literal, a config value, a comment. **Exit 0 with output means it found
something: downgrade that finding to Group 3, no exceptions.** This is the
single cheapest check in the whole command and it is not optional — skip it
once, ship a false "delete this" on the first run, and there won't be a
second run. See `05-design-rationale.txt`, decision 4.

This check applies to file-level Group 1 candidates. It doesn't apply to
unused-dependency or unused-export findings the same way (there's no
"file name" to search for) — use ordinary judgment and the false-positive
list for those instead.

## Step 4 — End with a change-proposal draft. Never delete anything.

Write `dead-code-report.md` at the repo root (overwrite the previous run's
copy — that's what makes `git diff dead-code-report.md` between runs show
exactly what's new and what got resolved). Structure per
`references/report-template.md`: three groups, each finding's source and
reasoning, and a closing recommendation to run `opsx-propose-review` with
Group 1 as its own isolated task group and Groups 2-3 as judgement-heavy
groups — so `spec-review`'s later classification lines up with this report's
own confidence levels. From there the normal process takes over: its own
branch, its own commits, the usual checks before push. **This command's job
ends at the draft. It does not create the change, does not edit source, and
does not delete a single file.** The real protection against a wrong
deletion is the existing pipeline — typecheck/lint on commit, tests before
push — and a command that deletes on its own would bypass that pipeline
instead of feeding it.

## Recording rejections

When a human looks at a Group 1/2/3 finding and decides it's wrong (a false
positive the checks above missed), record it — don't just drop it from this
run's report and let it come back next time:

```
scripts/record-rejection.sh <category> <name> "<reason>" [project-dir]
```

`category` is one of `file`, `dependency`, `binary`, `unresolved`, `export`,
`type` — it maps to knip's own `ignoreFiles` / `ignoreDependencies` /
`ignoreBinaries` / `ignoreUnresolved` / `ignoreIssues` config keys. This
writes into the project's own knip config (`knip.json`/`knip.jsonc`, created
if neither exists yet — a normal file to have), never into this plugin's
settings: knip already reads that file, so the exception takes effect for
free, and there's no second "what to ignore" list to drift out of sync with
the first. Every entry carries the reason as a comment; a plain `knip.json`
is migrated to `knip.jsonc` the first time a comment is needed (`knip.json`
itself doesn't tolerate comments — see the script's own header). Three
things fall out of this for free, and are worth being explicit about in the
report: each next report gets shorter instead of re-flagging the same
rejected items forever; the diff between runs stays readable; and the knip
config gradually becomes a written record of every place in the project
where ordinary static analysis is known to be wrong — useful to people
reading it, not just to this command. A JS/TS knip config
(`knip.config.ts`/`.js`) or a `knip` key embedded in `package.json` is out
of scope for this script; it prints the category/name/reason for you to add
by hand instead of attempting to edit executable config.

## Not a gate

This command is not one of the six review gates and does not append to
`.claude/harness-log.jsonl` — adding a line here would distort the log's
skip-rate accounting for a command that, by design, doesn't run on every
task the way a gate does. Run it by hand, roughly monthly, alongside the
harness-diet review in `review-gates.md`.

## Deliberately not in this version

- No duplicate-code detection (jscpd or similar) — noisy, and "this is a
  duplicate" is a judgment call, not a fact the way "nothing imports this"
  is.
- No automatic action on Group 1, or anything else — see Step 4.
- No key in `.claude/harness.json` for what to ignore — that's knip.json's
  job; see "Recording rejections" above.
