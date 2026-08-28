---
name: web-qa
description: Manual QA pass on a change's UI flows in a real browser, using the Playwright MCP server. A must-pass gate with a fix loop, run once per change on its last task group, before code-review. Not applicable to changes with no user-facing surface.
---

Run **Gate 3** of this project's review pipeline: web QA.

## Trigger

The *last* OpenSpec task group with pending tasks, once its implementation
is green (typecheck/lint/tests pass), and **before** Gate 4 (code-review).
Groups that aren't the last one skip this gate entirely — a full browser
pass runs once per change, not once per group.

## Applicability

Only when the change touched user-facing UI/flows. If the diff is
config/docs/CI-only, this gate is not applicable — say so and go straight to
Gate 4.

## Read the stack manifest, then run the dev server as a scoped background process

1. Read `.claude/harness.json` (written by `init-harness`) for `framework`,
   `runCmd`, `scripts.dev`, `devServerUrl`, and `webQaScenariosDir` (see
   "Replay recorded scenarios" below). Do not re-detect the
   framework from config files or the package manager from lockfiles — that
   duplicated logic is exactly what caused this skill to drift out of sync
   with `init-harness` before (it didn't know about `next.config.mjs`). If
   the manifest is missing, stop and tell the user to run `init-harness`
   first — see
   `${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/stack-detection.md`
   for what it detects.
2. Confirm Playwright's browsers are installed before starting anything:
   `npx playwright install --with-deps chromium` (add other engines only if
   this change's flows need them). On a machine that already has them this
   is a fast no-op; skipping it means Gate 3 fails on a missing browser
   binary instead of on an actual app defect.

   This plugin's Playwright **MCP server** (distinct from the `playwright`
   test/browser-automation package, if the project also has that as a test
   dependency) stays resident for the whole session per `mcp-config.json`,
   regardless of whether this gate ever runs — there's no supported
   per-gate MCP toggle in this Claude Code version. If this project runs
   this gate often, install `@playwright/mcp` as a devDependency so `npx`
   resolves it locally instead of doing a registry check on every session
   start; if it rarely touches user-facing UI, the README recommends
   disabling the server via `/mcp` for sessions that won't use it.
3. Start the dev server **in the background** (`run_in_background` on the
   Bash tool, or the run harness's background-job equivalent) — never
   foreground, since `<runCmd> <scripts.dev>` (e.g. `yarn dev`, `npm run
   dev`, `pnpm dev`) is a long-lived process that would otherwise block the
   rest of this gate. Keep its stdout readable and note its PID/job id for
   teardown below.
4. **Read the actual URL the dev server printed** — don't treat
   `devServerUrl` from the manifest as authoritative. Vite (and other dev
   servers) silently bump to the next free port when the configured one is
   taken, e.g. `5173` busy → `5174`, and print the real address to stdout on
   startup (`Local: http://localhost:5174/`). Poll the background process's
   output for that line and parse the live URL out of it, bounded to ~30s at
   1-2s intervals. Handing the manifest's `devServerUrl` to the reviewer
   unconditionally risks QA-ing a stale server left over from a previous
   session on the configured port, while this change's own server sits
   untested on the port it actually bound. If the expected startup line
   never appears in that window (crash, unfamiliar dev-server output
   format), stop, tear down (below), and report the captured stdout/stderr
   as a Gate 3 failure rather than guessing at a URL.
5. Poll the real URL for a `2xx`/HTML response before handing off to the
   reviewer, bounded to ~60s at 1-2s intervals — don't let the QA pass start
   against a server that's still compiling, but also don't let a server that
   never comes up hang the gate forever. If the timeout is hit, tear down
   (below) and report it as a Gate 3 failure.

## Replay recorded scenarios before the manual pass

Read `.claude/harness.json`'s `webQaScenariosDir` key (a repo set up by a
version of `init-harness` older than the one that added this key won't have
it — tell the user to re-run `init-harness` to pick it up, then continue
without a replay this time rather than blocking the gate on it). If the
directory exists and holds at least one recorded scenario file, run the
accumulated suite first: `npx playwright test <webQaScenariosDir>`. Zero
model tokens, seconds instead of a click pass.

This is the only part of this gate that checks flows the *current* diff
didn't touch: cart changing what it hands off to checkout doesn't necessarily
show up in checkout's own diff, and the manual pass below stays scoped to
this change's diff, not the whole app, so nothing else in this gate would
ever re-open checkout on its own. See
`harness-audit/v0.4.0-implemented/01-review-blind-spots.txt` point 3 for the
incident this closes.

- **Any failure here** feeds into the same fix loop as a manual-tester FAIL,
  below — a regression the replay catches is exactly as real as one the
  model finds by clicking, and blocks Gate 4 the same way.
- **All-PASS, or nothing recorded yet** → continue to the manual pass
  unchanged. A recorded scenario that's stale (selectors renamed, flow
  restructured) will surface as a failure here too, on its own — treat that
  the same as any other fix-loop failure rather than deleting the scenario
  to make the gate green.

## Action

1. Read `.claude/harness.json`'s `models.webQa` key (written by
   `init-harness`) and pass it as the `model` parameter when delegating to
   the `web-qa-manual-tester` subagent (`Agent` tool) — overriding the
   agent's own frontmatter default for this run. If the manifest or the key
   is missing, fall back to the agent's own default; never block the gate on
   a missing override. The subagent drives the **Playwright MCP server**
   (navigate, click, fill, snapshot via the accessibility tree, screenshot)
   against the running dev server — this plugin's own pinned server only
   (`mcp__plugin_sdd-harness-web-ykryshtopa_playwright__browser_*`), never a
   Playwright MCP the project or the user supplies at some other version;
   the reasoning is in `agents/web-qa-manual-tester.md`. Disabled via `/mcp`
   → the agent refuses to launch, which is the intended loud failure. Scope
   its flows to the *whole change's* diff against the parent branch, not
   just the last group, so the final pass covers everything the change
   touched — the replay above already re-verified whatever earlier changes
   recorded, so this pass is what covers what's actually new — including
   the UI States Matrix `agents/web-qa-manual-tester.md` requires for each
   touched surface. An unaddressed state reads the same as an unexercised
   flow: incomplete, not a pass by default. **States, per surface, first
   match wins:** `design.md`'s Mermaid `sequenceDiagram` for that flow, if found (error branches plus happy path) → those states, overriding the subagent's default; else `ui-plan.md`'s screen row matching the flow's destination screen by screen name (a multi-screen flow consults each row crossed), if found → its states column, overriding the default the same way; else the subagent's own default matrix.
2. The subagent relays a per-flow PASS/FAIL report, the per-surface UI
   States Matrix (loading/error/empty/offline, syncing/conflict only with
   background sync, each PASS/FAIL or not-applicable-with-reason, never
   silent), and a per-surface Keyboard Pass — reachability, focus
   visibility, tab order, modal focus-trap/Escape, same format, reported
   beside the matrix, not folded into it (`agents/web-qa-manual-tester.md`).

## This is a must-pass gate with a fix loop, not CONFIRMED/PLAUSIBLE

- **All-PASS** (every flow, state, and keyboard-pass check that applies) → proceed to Gate 4.
- **Any FAIL**, in a flow, state, or keyboard-pass check → run the
  `debug-loop` skill, scoped to what failed:
  reproduce / isolate (its environment-first check — rule out a third-party
  API rate limit, flaky animation timing, note it and re-run rather than
  treating it as a defect, though the app must still degrade gracefully — is
  what used to be this step's own step 1) / diagnose with a recorded
  expected effect / fix and reverify that exact scenario, bounded by
  `.claude/harness.json`'s `maxFixAttempts` (default 2). An approved fix
  folds into this group's own diff, so `code-review` (Gate 4 + Gate 5)
  reviews it too, and this gate re-runs on the affected flow(s) after each
  attempt.
  - **All-PASS within the limit** → proceed to Gate 4.
  - **Limit exhausted** → `debug-loop` escalates (blocked-marker + hypothesis
    report to the human). Do not proceed to Gate 4 on the default path. The
    only exception is an explicit human "proceed anyway," recorded in the
    group's commit body.

## Propose recording a passed scenario as a Playwright test

Once a flow reaches a final PASS — first try, or after the fix loop settles
— **propose** saving it as a regular Playwright test in the project, one
flow at a time. Never record automatically, and never bundle more than one
flow into a single yes/no: the human decides per scenario, because a report
that records everything that happened to pass turns into a pile of
overlapping, half-duplicate tests within a few months, and that pile is a
maintenance debt, not a safety net — see
`harness-audit/v0.4.0-implemented/05-design-rationale.txt` decision 6.

1. Ask (`AskUserQuestion` fits well here — one scenario, a clear yes/no) for
   each individually-passed flow, after the whole gate's fix loop has
   settled — don't ask mid-fix-loop about a flow that might still fail. A
   flow that's one-off, purely cosmetic, or mostly asserted "eyeballed by the
   model" content is a reasonable one to decline; a flow worth protecting
   against exactly the March/April checkout-vs-cart regression above is a
   reasonable one to keep.
2. On accept, read `.claude/harness.json`'s `webQaScenariosDir` key for
   where the file goes; write `<webQaScenariosDir>/<flow-slug>.spec.ts`
   (kebab-case from the flow's name), authored against `@playwright/test`'s
   own API (`page.goto`, `page.getByRole(...).click()`,
   `expect(...).toBeVisible()`, …) — translate the steps the MCP session
   actually took into their `@playwright/test` equivalents, not a literal
   transcript of MCP tool calls, which don't run outside that server.
3. **First scenario ever recorded in this project**: `permissions.deny`
   (written by `init-harness`) blocks every package manager's install
   command, on purpose, and this gate doesn't get an exception. If
   `@playwright/test` isn't already a devDependency, stop and ask the user
   to run `<pm> add -D @playwright/test` themselves, then continue once
   they confirm; likewise, if no `playwright.config.ts`/`.js` exists yet,
   write a minimal one with `testDir` pointing at `webQaScenariosDir` — if
   one already exists, only check it covers that directory and tell the
   user if it doesn't, rather than rewriting a config they may have tuned.
4. Run `npx playwright test <the new file>` right after writing it, before
   calling the scenario recorded. A file that doesn't pass standalone
   protects nothing — it just looks like coverage. Fix it or don't keep it;
   don't leave a red spec file behind silently.
5. Tell the user plainly what got recorded and what got declined this run —
   the report from step 1's per-flow answers, not a single aggregate line.

## Tear down the dev server whenever this gate exits

Stop the background dev server using the PID/job id captured at startup
(e.g. `kill <pid>`) on **every** exit path out of this gate, not only the
happy one: the fix loop settling (all-PASS, or an explicit human override),
a startup/health-check timeout (steps 4-5 above), or the
`web-qa-manual-tester` subagent erroring out before producing a verdict. A
server left running past this gate leaks a process for the rest of the
session and can collide with whatever the next gate or group needs on the
same port.

## Log this gate's run

After the fix loop settles (all-PASS, or an explicit human override), append
one line to `.claude/harness-log.jsonl` in the target repo (create the file
if it doesn't exist yet) — a plain shell append, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "-" \
  --arg gate "web-qa" \
  --arg verdict "<clean|confirmed|skipped>" \
  --arg skipReason "<интерфейс не затронут, when verdict is skipped; empty otherwise>" \
  --argjson durationMs <elapsed-ms> \
  --argjson tokensTotal <subagent_tokens from the <usage> block, 0 when skipped> \
  --arg model "<model web-qa-manual-tester actually ran on>" \
  --arg reviewConfidence "<high|low, from web-qa-manual-tester's own Output; empty when skipped>" \
  --argjson fixIterations <total debug-loop attempts across every FAIL this run, 0 if none> \
  --argjson escalatedToHuman <true iff any debug-loop invocation this run hit maxFixAttempts> \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, `verdict` as `clean` for all-PASS, `confirmed` for
any FAIL found along the way (even if later fixed and re-passed), or
`skipped` when this gate wasn't applicable; the wall-clock time across the
whole fix loop; and the model `web-qa-manual-tester` ran on (`group` is `-`:
this gate covers the whole change, triggered on the last group). `skipReason`
is the closed-list reason matching this gate's own applicability check —
`интерфейс не затронут` exactly when `verdict` is `skipped`, empty
otherwise. Also fill in its stated `reviewConfidence`, empty when skipped.
`tokensTotal` is the `subagent_tokens` figure from the `<usage>` block the
environment appends after the `web-qa-manual-tester` delegation returns
(point 5, `harness-audit/v0.4.0-implemented/03-log-fields.txt`), `0` when
skipped or when that block is absent — never estimate it from a proxy.
`fixIterations` is the attempt count `debug-loop` itself reports back (phase
4's "report success and the number of attempts it took"), summed if more
than one flow needed its own invocation this run; `0` when every flow
passed on the first try or the gate was skipped. `escalatedToHuman` is
`true` only if `debug-loop` reached `maxFixAttempts` on this run without
resolving a failure — the same run that then wrote a `blocked` marker
instead of proceeding. If `jq`
isn't available, construct the equivalent JSON line with `printf` instead.
A failed log write never blocks the gate — note it in the report and move
on; this is a diagnostic aid, not part of the pass/fail logic.
