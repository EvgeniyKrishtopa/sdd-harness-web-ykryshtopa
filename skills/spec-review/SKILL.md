---
name: spec-review
description: Reviews a complete OpenSpec change (proposal, design, specs, tasks) for internal consistency, testable requirements, and traceability, and classifies each task group in tasks.md as isolated or judgement-heavy. Use after the full artifact set is drafted, before implementing or archiving a change.
---

Run **Gate 2** of this project's review pipeline: spec review.

## Trigger

Every artifact required by the OpenSpec schema is `status: "done"` (for the
`spec-driven` schema: proposal + design + specs + tasks all complete).

## Action

1. Read `.claude/harness.json`'s `models.spec` key (written by
   `init-harness`) and pass it as the `model` parameter when delegating to
   the `spec-reviewer` subagent (`Agent` tool) for the whole change —
   overriding the agent's own frontmatter default for this run. If the
   manifest or the key is missing, fall back to the agent's own default;
   never block the gate on a missing override.
2. Beyond surfacing gaps, this is also where **task-group classification**
   happens: the reviewer marks each `## N.` heading in `tasks.md` as
   `isolated` or `judgement-heavy`, written back as a trailing
   `<!-- isolated -->` / `<!-- judgement-heavy -->` HTML comment on the
   heading. This classification is independent of findings — record it even
   on an otherwise clean review — and it is what `opsx-apply-git` reads to
   decide how far it can proceed autonomously. An unmarked group is treated
   as `judgement-heavy` downstream — never let a group run unattended if
   nobody classified it.
3. If the change is non-trivial (many groups, cross-cutting groups), think
   through the isolated vs judgement-heavy call per group explicitly, rather
   than eyeballing it — native extended thinking covers this in one pass; the
   `sequential-thinking` MCP server this project used to require for it is
   redundant with that and has been removed (cost-optimization #39).
4. Traceability is ID-based, not a general impression: `spec-reviewer`'s
   checklist item 1 collects every `FR-`/`NFR-` identifier `proposal.md`
   defines and checks `tasks.md` for both directions — every identifier
   named by a task, every task naming an identifier. A change whose
   `proposal.md` carries no identifiers is reported as **"traceability
   unavailable"**, never as passing; see `agents/spec-reviewer.md`.

`tasks.md` carries a third, unrelated marker this skill never writes:
`<!-- blocked: <reason> -->`, on an individual task's own checkbox line
rather than a group's `##` heading. `opsx-apply-git` writes that one, at the
moment a run stops without resolving the task — it has nothing to do with
this skill's isolated/judgement-heavy classification, which is decided
before implementation ever starts. Don't conflate the two when reading
`tasks.md` back.

## Handling the result

- **CONFIRMED finding** — show it to the user and ask whether to revise the
  relevant artifact(s) before declaring the change ready for implementation.
- **Clean, or PLAUSIBLE-only** — declare the change ready for implementation.
  The classification is still recorded either way.

## Log this gate's run

After delivering the verdict above, append one line to
`.claude/harness-log.jsonl` in the target repo (create the file if it
doesn't exist yet) — a plain shell append, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "-" \
  --arg gate "spec-review" \
  --arg verdict "<clean|plausible|confirmed>" \
  --argjson durationMs <elapsed-ms> \
  --arg model "<model spec-reviewer actually ran on>" \
  --arg reviewConfidence "<high|low, from spec-reviewer's own Output>" \
  --argjson fixIterations 0 \
  --argjson escalatedToHuman false \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,durationMs:$durationMs,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, the verdict this run resolved to, the wall-clock
time spent from delegating to `spec-reviewer` to receiving its response, the
model it actually ran on (`group` is `-`: this gate runs at change
scope), and its stated `reviewConfidence`. `fixIterations`/`escalatedToHuman`
are always `0`/`false` here, literally — never computed — because this gate
runs before implementation starts; there is no `debug-loop` fix cycle for
either field to describe. If `jq` isn't available, construct the equivalent JSON line with
`printf` instead. A failed log write never blocks the gate — note it in the
report and move on; this is a diagnostic aid, not part of the pass/fail
logic.
