---
name: architecture-review
description: Reviews an OpenSpec design.md, or a diff, for architecture risks — boundary violations, mixed concerns, god components/services, circular dependencies, duplicated domain logic, unnecessary global state. Use right after a design.md is drafted, before committing any change touching 2+ layers, or for any high-risk change.
---

Run **Gate 1** of this project's review pipeline: architecture review.

## Model

Before delegating, read `.claude/harness.json`'s `models.architecture` key
(written by `init-harness`) and pass it as the `model` parameter on the
`Agent` tool call, overriding `architecture-reviewer`'s own frontmatter
default for this run. If the manifest or the key is missing, fall back to
the agent's own default — a missing override never blocks the gate.

## Route

Also read the target change's route: the first line of
`openspec/changes/<change>/.route` (written by `opsx-propose-review`'s size
assessment), `short` or `full`. If the file is missing — an older change, a
diff not tied to any OpenSpec change, or a repo that hasn't upgraded to this
version — treat it as `full`; never assume a change opted into the cheaper
route it never asked for.

## When invoked against a design artifact (no diff yet)

1. Read the OpenSpec change's `design.md` (or equivalent proposal doc).
2. Delegate to the `architecture-reviewer` subagent (`Agent` tool, model per
   the note above), pointing it at the design artifact's path — it reviews
   the *proposed* architecture, not a diff, because none exists yet at this
   point in the workflow.
3. On a **full** route, think through the boundary/coupling implications
   step by step before handing a verdict to the user, rather than
   pattern-matching a snap judgment — native extended thinking covers this
   in one pass; the `sequential-thinking` MCP server this project used to
   require for it is redundant with that and has been removed
   (cost-optimization #39). On a **short** route, skip straight to the
   agent's own verdict — the checklist itself still runs in full; only this
   extra deliberation pass is size-gated.

## When invoked against a diff

1. Run `git diff` (or `git diff --cached` if the target is staged) against
   the parent branch.
2. Delegate to `architecture-reviewer` (model per the note above) with that
   diff.

## Handling the result

- **CONFIRMED finding** — show it to the user and ask whether to revise the
  design/diff now or proceed anyway. Do not silently continue past an
  unresolved CONFIRMED finding.
- **Clean, or PLAUSIBLE-only** — continue the workflow (artifact-creation
  loop, or straight to the next gate).

Never invent your own architecture criteria here — all of the actual review
logic lives in `architecture-reviewer`; this skill only orchestrates when it
runs and what happens with its verdict.

## Log this gate's run

After delivering the verdict above, append one line to
`.claude/harness-log.jsonl` in the target repo (create the file if it
doesn't exist yet) — a plain shell append, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "<route: short|full>" \
  --arg gate "architecture-review" \
  --arg verdict "<clean|plausible|confirmed>" \
  --arg skipReason "" \
  --argjson durationMs <elapsed-ms> \
  --argjson tokensTotal <subagent_tokens from the <usage> block> \
  --arg model "<model architecture-reviewer actually ran on>" \
  --arg reviewConfidence "<high|low, from architecture-reviewer's own Output>" \
  --argjson fixIterations 0 \
  --argjson escalatedToHuman false \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, the verdict this run resolved to, the wall-clock
time spent from delegating to `architecture-reviewer` to receiving its
response, the model it actually ran on (`group` carries this run's route,
`short` or `full`, in place of the task-group id this gate has none of —
it always runs at change scope), and its stated `reviewConfidence`.
`skipReason` is always empty here — this gate never logs `verdict:
"skipped"` itself. `tokensTotal` is the `subagent_tokens` figure from the
`<usage>` block the environment appends after the `architecture-reviewer`
delegation returns (see `harness-audit/v0.4.0-implemented/03-log-fields.txt`
point 5) — never estimate this from `durationMs` or any other proxy; if
that block is absent, write `0` and say so in the report rather than
guessing.
`fixIterations`/`escalatedToHuman` are always `0`/`false` here, literally —
never computed — because this gate reviews a proposed design or a diff
directly; there is no `debug-loop` fix cycle attached to Gate 1 for either
field to describe. If `jq` isn't available, construct the
equivalent JSON line with `printf` instead. A failed log write never blocks
the gate — note it in the report and move on; this is a diagnostic aid, not
part of the pass/fail logic.
