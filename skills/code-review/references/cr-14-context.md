# CR-14 context — 0 tokens, before delegating

Read from `SKILL.md` "Test plan". `code-reviewer`'s CR-14 (a new flow or
service boundary with no test) only judges what this step hands it; it
cannot read the manifest or the log itself without spending tokens on it.
Build two parts and pass them next to the test plan.

## Flows

First match wins:

1. No `tests.e2e` block in `.claude/harness.json`, or its
   `replayBeforePush` is `false` → `flows: not applicable — tests.e2e not
   configured`.
2. Not the change's final run (`SKILL.md` Action step 3 — compute it first)
   → `flows: not applicable — scenarios are recorded on the last group`.
   On an early run a missing scenario is normal, not a gap.
3. Otherwise pass:
   - the scenarios directory: `jq -r '.tests.e2e.dir // .webQaScenariosDir
     // "tests/web-qa-scenarios"' .claude/harness.json`;
   - this change's `recordedFlows` and `declinedFlows`, from every
     `web-qa-flows` line it has (a change can run `web-qa` more than once):
     ```bash
     { cat .claude/harness-log.jsonl; find .claude/harness-log -name '*.jsonl' -exec cat {} +; } 2>/dev/null \
       | jq -R 'fromjson?' | jq -sc --arg c "<change-slug>" \
       '[.[] | select(.change == $c and .kind == "web-qa-flows")]
        | {recordedFlows: (map(.recordedFlows[]?.flow) | unique),
           declinedFlows: (map(.declinedFlows[]?) | unique)}'
     ```
   - whether `web-qa` ran in this change at all: a `gate:"web-qa"` line
     without `kind` and with `verdict` other than `skipped`. None → say
     "web-qa never ran in this change".

   `fromjson?` skips a broken line instead of failing the whole read. No
   log → both lists empty, and web-qa never ran. The log is one file per
   branch since 0.12.0 (`skills/opsx-apply-git/references/log-findings.md`,
   "Where the log lives"); the line above reads all of them.

## Boundaries

1. No `tests.integration` block → `boundaries: not applicable —
   tests.integration not configured`.
2. Otherwise pass the definition file's path,
   `${CLAUDE_PLUGIN_ROOT}/skills/opsx-apply-git/references/integration-tests.md`,
   and the template it points to
   (`${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/local-stack-profile.md`
   section 2). Boundaries apply on every run, not only the last: the group
   that adds a boundary writes its integration test itself.
