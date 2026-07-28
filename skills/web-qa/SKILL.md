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

## Detect the framework before starting the dev server

1. Check for `next.config.js`/`next.config.ts`/`next.config.mjs` → Next.js
   project: start with `next dev` (default port 3000, or read `-p` from an
   existing script in `package.json`).
2. Otherwise check for `vite.config.js`/`vite.config.ts` → Vite project:
   start with `vite` / `npm run dev` (default port 5173).
3. Use whichever package manager's lockfile is present (`yarn.lock` →
   `yarn dev`, `package-lock.json` → `npm run dev`, `pnpm-lock.yaml` →
   `pnpm dev`) rather than assuming one.
4. Confirm the dev server is actually up (poll the root URL) before handing
   off to the reviewer — don't let the QA pass silently test against a dead
   server.

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
