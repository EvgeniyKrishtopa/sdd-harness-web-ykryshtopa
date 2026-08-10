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
   never block the gate on a missing override. Also read the manifest's
   `disabledRules` array and pass it along as context — an empty array or
   missing key means nothing is disabled; never invent a value. Also read
   the change's route — the first line of
   `openspec/changes/<change>/.route` (written by `opsx-propose-review`'s
   size assessment), `short` or `full`; if the file is missing, treat it as
   `full` — never assume a change opted into the cheaper route it never
   asked for.
2. Beyond surfacing gaps, this is also where **task-group classification**
   happens: the reviewer marks each `## N.` heading in `tasks.md` as
   `isolated` or `judgement-heavy`, written back as a trailing
   `<!-- isolated -->` / `<!-- judgement-heavy -->` HTML comment on the
   heading. This classification is independent of findings — record it even
   on an otherwise clean review — and it is what `opsx-apply-git` reads to
   decide how far it can proceed autonomously. An unmarked group is treated
   as `judgement-heavy` downstream — never let a group run unattended if
   nobody classified it.
3. On a **full** route, think through the isolated vs judgement-heavy call
   per group explicitly, rather than eyeballing it — native extended
   thinking covers this in one pass; the `sequential-thinking` MCP server
   this project used to require for it is redundant with that and has been
   removed (cost-optimization #39). On a **short** route, skip straight to
   the classification — the checklist below still runs in full; only this
   extra deliberation pass is size-gated.
4. Traceability is ID-based, not a general impression: `spec-reviewer`'s
   checklist item 1 collects every `FR-`/`NFR-` identifier `proposal.md`
   defines and checks `tasks.md` for both directions — every identifier
   named by a task, every task naming an identifier. A change whose
   `proposal.md` carries no identifiers is reported as **"traceability
   unavailable"**, never as passing; see `agents/spec-reviewer.md`.
5. **Readiness checklist — assemble and print always, clean run or not.**
   Five conditions, each named individually when unmet — never a generic
   "not ready":
   1. **Every required artifact is `status: "done"`** — re-confirm directly
      against `proposal.md`/`design.md`/the spec deltas/`tasks.md`, the
      same signal this skill's own Trigger already relies on; name
      whichever one isn't.
   2. **Every `FR-`/`NFR-` identifier is traced** — reuse step 4's own
      result: pass, name the orphan identifier or task, or
      **"traceability unavailable"** under the same rule as step 4.
   3. **Every `tasks.md` group is classified** — reuse step 2's own
      classification; name any `## N.` heading still missing its
      `<!-- isolated -->`/`<!-- judgement-heavy -->` marker.
   4. **No open question is missing an owner or a due date** — read
      `proposal.md`'s `## Open Questions` section, if it has one, and check
      every entry `spec-clarify` writes (`- <file>:<line> — <finding> —
      owner: <owner>, due: <date>`) actually carries both fields; name any
      that doesn't. **Not applicable** if the repo has no `CONTEXT.md` at
      its root — this project hasn't been upgraded to the version that adds
      `spec-clarify`, so it can't have produced entries in this shape.
   5. **No domain term the change uses contradicts the glossary** — reuse
      `spec-reviewer`'s SR-05 result: pass, name the contradicting term, or
      **not applicable** under the same `CONTEXT.md`-absence rule as
      condition 4. This is narrower than "every term is defined" — SR-05
      only flags a term used against a meaning `CONTEXT.md` already states,
      not one missing from the glossary entirely; that's outside its scope
      today.

   An unmet condition (never one marked N/A) is handled exactly like a
   CONFIRMED finding below — name it, and don't declare the change ready
   until the user has seen it. Log each one as its own `kind: "finding"`
   line per `skills/opsx-apply-git/references/log-findings.md`'s shape —
   `gate: "spec-review"`, `finding`: which condition and what's missing,
   `outcome`: `"fixed"` (artifact revised on the spot), `"deferred"`
   (condition 4 only — logged under Open Questions with an owner and due
   date), or `"rejected"` (the user chose to proceed anyway), `ruleNumber`:
   empty — these conditions aren't numbered rules. This is what actually
   makes "how often did work start against incomplete readiness"
   answerable later; the gate-run `verdict` below only says *that*
   something was unresolved, never *which* condition.

`tasks.md` carries a third, unrelated marker this skill never writes:
`<!-- blocked: <reason> -->`, on an individual task's own checkbox line
rather than a group's `##` heading. `opsx-apply-git` writes that one, at the
moment a run stops without resolving the task — it has nothing to do with
this skill's isolated/judgement-heavy classification, which is decided
before implementation ever starts. Don't conflate the two when reading
`tasks.md` back.

## Handling the result

- **CONFIRMED finding, or an unmet readiness condition (the checklist
  above)** — show it to the user and ask whether to revise the relevant
  artifact(s) before
  declaring the change ready for implementation. Log this run's `verdict`
  as `"confirmed"` even when `spec-reviewer` itself came back clean — an
  unmet readiness condition must not slip through silently just because
  nothing else was wrong — and log each unmet condition itself per the
  `kind: "finding"` instructions in the checklist above.
- **Clean, or PLAUSIBLE-only, and every readiness condition met or N/A** —
  declare the change ready for implementation. The classification is still
  recorded either way.

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
  --arg gate "spec-review" \
  --arg verdict "<clean|plausible|confirmed>" \
  --arg skipReason "" \
  --argjson durationMs <elapsed-ms> \
  --argjson tokensTotal <subagent_tokens from the <usage> block> \
  --arg model "<model spec-reviewer actually ran on>" \
  --arg reviewConfidence "<high|low, from spec-reviewer's own Output>" \
  --argjson fixIterations 0 \
  --argjson escalatedToHuman false \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, the verdict this run resolved to (per "Handling
the result" above, `confirmed` also covers an unmet readiness condition,
not only a `spec-reviewer` finding — this line alone only says *that* the
run wasn't clean; the per-condition `kind: "finding"` lines are what say
*which* condition it was), the wall-clock time spent from delegating to
`spec-reviewer` to receiving its
response, the model it actually ran on (`group` carries this run's route,
`short` or `full`, in place of the task-group id this gate has none of — it
always runs at change scope), and its stated `reviewConfidence`. `skipReason` is always empty
here — this gate never logs `verdict: "skipped"` itself. `tokensTotal` is
the `subagent_tokens` figure from the `<usage>` block the environment
appends after the `spec-reviewer` delegation returns (see
`harness-audit/v0.4.0-implemented/03-log-fields.txt` point 5) — never estimate
this from `durationMs` or any other proxy; if that block is absent, write
`0` and say so in the report rather than guessing.
`fixIterations`/`escalatedToHuman`
are always `0`/`false` here, literally — never computed — because this gate
runs before implementation starts; there is no `debug-loop` fix cycle for
either field to describe. If `jq` isn't available, construct the equivalent JSON line with
`printf` instead. A failed log write never blocks the gate — note it in the
report and move on; this is a diagnostic aid, not part of the pass/fail
logic.
