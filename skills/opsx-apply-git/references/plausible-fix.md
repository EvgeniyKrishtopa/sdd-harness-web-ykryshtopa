# PLAUSIBLE findings in a judgement-heavy run — §4 step 2

Read this on a **Case B** run whose review came back with at least one
PLAUSIBLE finding (from `code-reviewer`, either section, or `deep-reviewer`)
and no CONFIRMED one left open. Case A is not affected: an isolated batch
still continues past PLAUSIBLE findings without asking.

## Why ask

The human is already in the loop for this run, and a PLAUSIBLE finding is
exactly the kind the reviewer couldn't prove alone — the human can. Before
0.12.0 such a finding was only printed, so a fix happened only if the agent
thought of offering one.

## The question

Before step 3, `AskUserQuestion` with **one question per finding**: the
question is the rule code and one line plus "Fix before push?", e.g.
`CR-03: the new formatPrice helper duplicates utils/money.ts — fix before
push?`, with exactly two options, **Fix** and **Keep as is**. No
`multiSelect`. A call holds at most four questions; more findings → a
second call for the rest, in the reviewer's order, until each one has had
its answer.

Why not one question with an option per finding: a question needs two to
four options, so a single finding (or the fifth of five) gave a question
the tool rejects. Two options per question is valid for any number of
findings.

## The answer

- **Fix** → fix each one as its own commit (`fix(<scope>): <rule code>
  <summary>`), staged by explicit path, never amended into the group's
  commit. Run the project's typecheck, lint and tests after the last one;
  a failure goes through `debug-loop`, as a CONFIRMED fix would.
- **Keep as is** → nothing changes in the code.
- No answer (the run ends first) → report the open findings by name and
  stop before the push.

Each finding gets one `kind:"finding"` line (`references/log-findings.md`):
`outcome` `fixed` for a "Fix" whose commit landed, `rejected` for a "Keep
as is". Both go into the PR's Review trail like any other finding.
