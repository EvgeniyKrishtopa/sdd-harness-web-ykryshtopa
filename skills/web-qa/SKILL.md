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
   `runCmd`, `scripts.dev`, and `devServerUrl`. Do not re-detect the
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
   dependency) stays resident for the whole session per `.mcp.json`,
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

## Action

1. Read `.claude/harness.json`'s `models.webQa` key (written by
   `init-harness`) and pass it as the `model` parameter when delegating to
   the `web-qa-manual-tester` subagent (`Agent` tool) — overriding the
   agent's own frontmatter default for this run. If the manifest or the key
   is missing, fall back to the agent's own default; never block the gate on
   a missing override. The subagent drives the **Playwright MCP server**
   (navigate, click, fill, snapshot via the accessibility tree, screenshot)
   against the running dev server. Those tools are named
   `mcp__plugin_sdd-harness-web-ykryshtopa_playwright__browser_*` when the
   server comes from this plugin's own `.mcp.json` — the bare
   `mcp__playwright__browser_*` form only applies when the project supplies
   Playwright MCP itself; the agent's `tools:` list carries both spellings
   for that reason. Scope its
   flows to the *whole change's* diff against the parent branch, not just
   the last group, so the final pass covers everything the change touched
   — including the UI States Matrix (loading/error/empty/offline)
   `agents/web-qa-manual-tester.md` requires for each touched surface. An
   unaddressed state reads the same as an unexercised flow: incomplete, not
   a pass by default.
2. The subagent relays a per-flow PASS/FAIL report, plus the per-surface UI
   States Matrix — loading/error/empty/offline each PASS/FAIL or explicitly
   not applicable with a reason, never silently omitted; syncing/conflict
   included the same way only on a project with background sync, otherwise
   left out of the matrix entirely rather than marked not-applicable.

## This is a must-pass gate with a fix loop, not CONFIRMED/PLAUSIBLE

- **All-PASS** (every flow, and every applicable UI state) → proceed to
  Gate 4.
- **Any FAIL**, in a flow or in any applicable UI state → run the
  `debug-loop` skill, scoped to the failing flow(s) or state(s):
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
  --argjson durationMs <elapsed-ms> \
  --arg model "<model web-qa-manual-tester actually ran on>" \
  --arg reviewConfidence "<high|low, from web-qa-manual-tester's own Output; empty when skipped>" \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model,reviewConfidence:$reviewConfidence}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, `verdict` as `clean` for all-PASS, `confirmed` for
any FAIL found along the way (even if later fixed and re-passed), or
`skipped` when this gate wasn't applicable; the wall-clock time across the
whole fix loop; and the model `web-qa-manual-tester` ran on (`group` is `-`:
this gate covers the whole change, triggered on the last group). Also fill
in its stated `reviewConfidence`, empty when this gate was skipped. If `jq`
isn't available, construct the equivalent JSON line with `printf` instead.
A failed log write never blocks the gate — note it in the report and move
on; this is a diagnostic aid, not part of the pass/fail logic.
