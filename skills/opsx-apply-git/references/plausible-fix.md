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

Before step 3, one `AskUserQuestion` with `multiSelect: true`: **"Fix
before push?"**. One option per finding — its rule code and one line, e.g.
`CR-03: the new formatPrice helper duplicates utils/money.ts`. A question
holds at most four options, and a call at most four questions; more
findings → ask again for the rest, in the reviewer's order, until each one
has had its yes or no.

## The answer

- **Chosen** → fix each one as its own commit (`fix(<scope>): <rule code>
  <summary>`), staged by explicit path, never amended into the group's
  commit. Run the project's typecheck, lint and tests after the last one;
  a failure goes through `debug-loop`, as a CONFIRMED fix would.
- **Not chosen** → nothing changes in the code.
- No answer (the run ends first) → report the open findings by name and
  stop before the push.

Each finding gets one `kind:"finding"` line (`references/log-findings.md`):
`outcome` `fixed` for a chosen one whose commit landed, `rejected` for one
not chosen. Both go into the PR's Review trail like any other finding.
