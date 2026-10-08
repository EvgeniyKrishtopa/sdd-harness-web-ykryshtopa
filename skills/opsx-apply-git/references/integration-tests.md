# Integration tests written with the code — a new service boundary

Read from `SKILL.md` §3 (both cases) when `.claude/harness.json` has a
`tests.integration` block and the group adds a new boundary to a service.
Without the block, nothing here applies and the group behaves as before.
Background: `harness-audit/v0.11.0-planned/06-review-and-stats.txt`,
point 10.

A unit test with the service's client stubbed out proves only that the
code called the stub. The written rule has to sit where the code is
written: `code-review` (CR-14) catching a missing test afterwards is the
safety net, not the mechanism.

## What a boundary is

The **lowest** function that itself calls the client of a service the
local stack runs — a service whose address `tests.integration.envCommand`
prints. Not the functions that call it.

Example: a Server Action `signIn` calls `getUserByEmail` in `lib/dal.ts`,
and `getUserByEmail` calls the stack's client. The boundary is
`getUserByEmail`; the test goes there. `signIn` gets no integration test —
it calls a boundary that is already covered, it is not a new one.

A service outside the local stack (a hosted CMS, payments, a cloud mail
service) is not a boundary for this rule: integration tests never reach a
cloud service. Unit tests with a stub and the environment check cover it.

## What to write

`<name>.integration.test.ts` next to the boundary's file — or where the
project's existing integration tests already live, if it has some. Follow
`${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/local-stack-profile.md`
section 2: addresses and keys come from `inject('localStack')`, never from
`process.env` or a `.env*` file. Assert the service's real answer — e.g. a
wrong password returns the service's own error, and the code turns it into
the right result. Name the requirement identifier, as for every test.

With `makerChecker.enabled`, `test-author` writes this file before the code
(`references/maker-checker.md`), and this session writes none.

## Running it

Run `tests.integration.healthCheck` first, its output to `/dev/null`: only
the exit code matters, and a stack's status command can print its keys.

- **Passes** → run `<runCmd> <tests.integration.script>`. Red is red: the
  group is not green until it passes, the same as any other test.
- **Fails, or the run stops with the template's "Local services are not
  running"** → keep the test written. Add one line to the run's report:
  `integration test <file> not verified: start <requires>`. Do not stop
  the group and do not mark it `blocked` — its own unit tests, typecheck
  and lint decide whether it is green. What keeps an unverified test from
  reaching `main` unrun is `.husky/pre-push`, so check that it really runs
  them: `grep -qF -- "<tests.integration.script>" .husky/pre-push`. No
  match (a declined upgrade diff, a hand-edited hook) → end that report
  line with `— and .husky/pre-push doesn't run integration tests; ask
  init-harness to re-run anyway and add the pre-push block it offers`. Say the
  gap; never assume the hook covers it.
