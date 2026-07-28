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

1. Delegate to the `web-qa-manual-tester` subagent (`Agent` tool), which
   drives the **Playwright MCP server** (`mcp__playwright__*` tools —
   navigate, click, fill, snapshot via the accessibility tree, screenshot)
   against the running dev server. Scope its flows to the *whole change's*
   diff against the parent branch, not just the last group, so the final
   pass covers everything the change touched.
2. The subagent relays a per-flow PASS/FAIL report.

## This is a must-pass gate with a fix loop, not CONFIRMED/PLAUSIBLE

- **All-PASS** → proceed to Gate 4.
- **Any FAIL**:
  1. First rule out an environment condition (a third-party API rate limit,
     a flaky animation timing) — note it and re-run rather than treating it
     as a defect, though the app must still degrade gracefully.
  2. For a genuine failure, suggest a concrete fix and get the user's
     approval before changing anything.
  3. Apply the approved fix — it folds into this group's own diff, so Gate 4
     and Gate 5 review it too — and re-run `web-qa` on the affected flow(s).
     Repeat until all-PASS.
  4. Do not proceed to Gate 4 past a FAIL on the default path. The only
     exception is an explicit human "proceed anyway," recorded in the
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
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, `verdict` as `clean` for all-PASS, `confirmed` for
any FAIL found along the way (even if later fixed and re-passed), or
`skipped` when this gate wasn't applicable; the wall-clock time across the
whole fix loop; and the model `web-qa-manual-tester` ran on (`group` is `-`:
this gate covers the whole change, triggered on the last group). If `jq`
isn't available, construct the equivalent JSON line with `printf` instead.
A failed log write never blocks the gate — note it in the report and move
on; this is a diagnostic aid, not part of the pass/fail logic.
