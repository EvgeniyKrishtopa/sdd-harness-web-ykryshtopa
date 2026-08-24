# Turning a fixed defect into a permanent eval case

A record under `_debug/` explains a failure to a human. It checks nothing.
The failure it describes can come back in three months and the only thing
standing in its way is that somebody happens to remember reading the file.

For one kind of defect there is somewhere better to put it: this plugin's
own eval set (`evals/` in the plugin repo), where a case is re-measured
every time a skill description changes or a cheaper model is considered.
This is the same move `web-qa` already makes when it offers to keep a
passed browser flow as a permanent `@playwright/test` scenario.

## Only one of the two kinds of defect belongs there

**A defect in the project's own code** — a broken function, component or
query. It stays in the project: SKILL.md's case 1 already requires a test
pinning the exact scenario, and Gate 5 already measures whether such tests
exist. This plugin's eval set knows nothing about that codebase and must
not accumulate cases about it.

**A defect in the harness's own behaviour** — a gate that stayed silent on
something it is meant to catch, the wrong skill firing (or none), a
CONFIRMED that came back PLAUSIBLE, a rule code that never triggered.
Nothing else pins this: the gates do not review themselves, and the log
records only what did happen, never what should have. This is the kind the
eval set exists for.

The split signal, and it needs no model call: **where the fix landed.**
Files of the project → first kind. `skills/`, `agents/`, `hooks/`,
`.claude/harness.json`, or a rule's own wording → second kind.

**The border case, which is both.** A defect in the project's code that a
gate was supposed to catch and didn't. The test pinning the broken
behaviour goes into the project; a case pinning *the gate's silence* goes
into the eval set. Two different failures — "the code was wrong" and "the
review said nothing" — and fixing the first leaves the second untouched.

## Ask once, and only for the second kind

Ask after phase 4's reverification has confirmed the fix and SKILL.md's
three-case classification has run — not mid-loop, where it is still unknown
whether the failure is fixable at all. One `AskUserQuestion`, one yes/no.

Word the question as what is being pinned, not as filing: "keep it as a
permanent check that `code-review` stayed silent on an unawaited promise?"
— not "save an eval case?". A question whose answer costs nothing to give
gets answered without reading within a month.

For the first kind, do not ask at all. A question on every fixed defect is
a question nobody reads.

## Two branches: whose repository is this

The loop almost always runs inside somebody else's project, where this
plugin is merely installed. Its `evals/` directory is not there and must
not be created there.

Decide by one check — does this repo have `.claude-plugin/plugin.json` with
name `sdd-harness-web-ykryshtopa`?

**This plugin's own repo** (the maintainer debugging the harness on itself)
→ on a yes, write the case directly under `evals/regressions/<slug>/`.

**Someone else's project** → write nothing outside the project. Put the
draft into the debug record itself, under `## Eval-case candidate` (see
`debug-record.md`), and print one line telling the user it is there and
that it belongs in the plugin repo. The draft is written now, while the
failure's details are still on hand; moving it later costs one copy.

Never write outside the current project on this branch — not into the
plugin's install directory, not into a sibling checkout, not anywhere the
user did not ask you to write.

## What the case looks like

Same slug as the debug record. That is the whole cross-reference: from the
case you can find the debugging history, from the record you can find the
permanent check that grew out of it.

```
evals/regressions/<slug>/
  case.yaml            scaffold + the longer execution budget
  prompt.md            the request the gate stayed silent on, verbatim
  graders/*.md         what the gate was supposed to say
```

`case.yaml`:

```yaml
schema_version: "1.1"
name: <slug>
context:
  scaffold_script: ../../support/make-repo.sh
```

`prompt.md` carries the longer budget a real review needs, and names the
defect the scaffold must plant:

```markdown
---
name: <slug>
tags: [regression, <gate>]
plugins: ["../../.."]
runs: 1
max_turns: 12
timeout_seconds: 600
env:
  EVAL_DEFECT: <defect name registered in make-repo.sh>
---
<the request as the person actually made it>
```

Graders use the vocabulary the harness already has — rule codes and the two
verdicts — instead of inventing a score:

```markdown
---
type: regex
pattern: 'CR-\d+'
match: contains
---
The review must name the rule code it fired on.
```

```markdown
---
type: regex
pattern: 'CONFIRMED'
match: contains
---
The defect reproduces deterministically, so the verdict must be CONFIRMED,
not PLAUSIBLE.
```

Prefer this shape — a code and a verdict — over an LLM judge on the prose.
Keep in mind which gates it fits: `harness-review` deliberately does not
follow the CONFIRMED/PLAUSIBLE pause rule (see its SKILL.md), so a case
about that gate has to grade on the finding's content instead.

When it does, grade on **the claim, not the filename**. A gate that read
every file and reported nothing still names those files in its answer, so a
grader matching `CLAUDE\.md` alone passes on the exact silence the case was
written to catch. Require the two halves that only a real finding puts
together — the file *and* the wrong value in it:

```markdown
---
type: regex
pattern: 'CLAUDE\.md.{0,300}(\bsix\b|шесть)|(\bsix\b|шесть).{0,300}CLAUDE\.md'
flags: 'is'
match: contains
---
```

The general test for any grader, of any type: describe the run this case
exists to catch — the gate staying silent — and check that the grader would
fail it. If it would pass, the grader measures nothing.

## The defect goes into make-repo.sh, by name

The scaffold builds a clean minimal repository and then applies exactly one
named defect, selected by the case's `EVAL_DEFECT`. New case, new named
block in `evals/support/make-repo.sh` — roughly ten lines, and the defect
stays reviewable in one place instead of being spread across case files.

An unknown or empty `EVAL_DEFECT` makes the script exit non-zero on
purpose: a case that quietly got a clean repository would pass forever
while measuring nothing, which is the same failure mode as a grader
pointing at a skill name that does not exist.

Because a scaffold runs author-written bash, this set only runs when it is
asked for explicitly: `--scaffold --allow-tools Bash`. That is why the
regression set is a separate command from the routing set, which needs no
grants at all.

## When a case with that slug already exists

The same failure coming back is exactly what these cases exist to catch, so
finding one is a result, not a collision:

- **The existing case is red on the current model** → it already caught
  this. Do not write a second case; add the newly-found detail to the
  existing record's `## Outcome` and fix the harness.
- **The existing case is green and the failure still happened** → the case
  is measuring the wrong thing. Sharpen its graders or its prompt in the
  plugin repo, in the same change as the fix — do not add a near-duplicate
  case beside it. Two cases about one failure means neither gets read when
  one of them goes red.
- **The slug matches but the failure is genuinely different** → rename the
  new one so the slug describes *this* failure. Slugs name failures, not
  areas.
