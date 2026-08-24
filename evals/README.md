# `evals/` — the calibrated set this plugin is measured against

Three things measure this plugin, and until this directory existed only two
of them were here:

| Layer | What it answers | Where |
|---|---|---|
| Structural tests | Are the files present and are the schemas valid? | `tests/*.sh` |
| Production telemetry | What did the review pipeline actually do this month? | `.claude/harness-log.jsonl`, read by `harness-stats` |
| **This set** | **On a fixed list of prompts with a known right answer, did the plugin behave?** | `evals/` |

The first two can both look healthy while routing quietly regresses: a
structural test never reads a skill description, and telemetry only ever
records the skills that *did* fire — never the one that should have and
didn't. That blind spot is what this directory is for.

It is run by hand, by the maintainer, at three moments: after editing any
skill description, before accepting a cheaper model, and when a fixed
harness-level defect is turned into a permanent case. It is not wired into
any commit hook and not wired into CI.

## Layout

```
evals/
  README.md            this file
  baseline/            reference measurements, committed
  routing/             "does the right skill fire" cases
  regressions/         "did a review catch what it missed once" cases
  support/             shared material the sandbox needs
  .gitignore           results/
```

`results/` is where the runner writes each run. It is ignored on purpose —
a run is a draft. Only `baseline/` is committed.

## Case format

The format is Claude Code's own (`claude plugin eval`), not a local
invention. One case is one directory:

```
evals/routing/code-review-fires/
  prompt.md            frontmatter + the user's message
  graders/fires.md     frontmatter type: + what it checks
```

`prompt.md`:

```markdown
---
name: code-review-fires
tags: [routing, positive]
plugins: ["../../.."]
runs: 1
max_turns: 2
timeout_seconds: 120
---
Я закончил группу задач, всё зелёное. Посмотри изменения перед тем, как я
запушу.
```

`graders/fires.md`:

```markdown
---
type: tool_used
tool: Skill
input_match: '"skill"\s*:\s*"(?:[\w-]+:)?code-review"'
min: 1
---
`code-review` must fire on this request.
```

A "must not fire" grader is the same file with `min: 0` and `max: 0`.

Grader types available: `tool_used`, `regex`, `tool_order`, `file_exists`,
`llm`, `baseline`. Prefer the deterministic ones — an LLM judge needs its
own calibration kept up over time, which is the cost this set is explicitly
trying not to take on.

`plugins: ["../../.."]` is the path from the case directory up to the
plugin root. It is three levels for a case under `routing/` or
`regressions/`.

## The two sets differ in permissions

**Routing** (`evals/routing/`) needs no grants. The case only has to pick a
skill, so tools stay read-only and each case is capped at two turns.

```bash
claude plugin eval . --eval-dir evals --case 'routing/*' \
  --ablation none --model <model>
```

**Regressions** (`evals/regressions/`) need a repository with a defect
planted in it, which a case builds through `context.scaffold_script` in its
`case.yaml`. A scaffold runs author-written bash as you, so the runner
demands it be asked for explicitly:

```bash
claude plugin eval . --eval-dir evals --case 'regressions/*' \
  --ablation none --model <model> --scaffold --allow-tools Bash
```

Two flags worth knowing about either way:

- `--ablation none`. The runner's default is a second, no-plugin arm; for
  this plugin that arm is meaningless (without the plugin the skill does
  not exist) and it turns `Skill` graders into an unscored indicator.
- `--model`. The sandbox does not inherit `ANTHROPIC_MODEL`. Pin the model
  or two measurements are not comparable.

## Cost rules that hold the set together

- `runs: 1` for routing cases. The runner's default is 3; three runs across
  the whole routing set is 72 sessions per measurement, which is how a
  suite stops being run at all. `--runs 3` is applied case by case, when a
  case starts to flap.
- `max_turns: 2` for routing cases. Which skill to use is decided on the
  first turn; paying for the work afterwards measures nothing.
- The set grows on cause, not on schedule: a new case is written when
  something actually went wrong — a false fire, a miss, a disputed verdict.

`tests/smoke-json-schema.sh` enforces the first two on every run, so they
survive as a rule rather than as a good intention. It also checks that every
skill a grader names exists, that each grader's `type` is one the runner
knows, and that a case's frontmatter name matches its directory.

## Taking a baseline

A baseline is one measurement of the whole set on the model in use,
committed so a later run has something to be compared against:

```bash
claude plugin eval . --eval-dir evals --ablation none \
  --model <model> --json evals/baseline/<version>-<model>.json
```

Next to it, `evals/baseline/<same name>.meta`:

```
commit:  <the commit it was taken on>
model:   <model id>
date:    <date>
runs:    <runs per case>
note:    <ran with the CLI | measured by hand, early access not enabled>
```

`commit:` is what makes staleness detectable: `harness-review` compares it
against the last commit that touched `skills/*/SKILL.md` or `agents/*.md`
and says so when descriptions have moved on since. It reports; it does not
block and it does not edit anything.

## Reading a failure

A red case is a claim about the plugin, not about the case. The fix goes
into the skill description (its `SKILL.md` frontmatter) — never into the
prompt, because rewriting the requirement to match the behaviour deletes
the measurement.

- A positive case failed → the description does not reach the words a real
  user types.
- A negative case failed → the description of the skill that grabbed the
  request is too broad; state the boundary explicitly ("not for X — that's
  Y").

When a description changes, the baseline is retaken in the same change.
Otherwise the next person compares against a measurement of the old text.

## Availability

`claude plugin eval` is in early access and is enabled per organization.
Check with the command itself in an empty directory:

- `No eval cases found` → enabled.
- `` `plugin eval` is currently in early access `` → not enabled here.

While it is not enabled the cases are still the maintained, reviewable
statement of what this plugin must do, and the set can be measured by hand:
open a fresh session, paste a case's prompt, record whether the expected
skill fired, and keep the tally in `evals/baseline/manual-<date>.md` with
`note:` saying it was manual. Slow, but 24 short prompts once is a real
measurement, and a hand measurement is never silently mixed with a CLI one.
