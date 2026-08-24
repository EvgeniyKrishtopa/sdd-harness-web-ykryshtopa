---
name: harness-review
description: Reviews CLAUDE.md/AGENTS.md, .claude/harness.json, .claude/settings.json, .claude/docs/**, .husky/**, and openspec/config.yaml for stale claims and drift from authoring best practices — plus this plugin's own skills/ and agents/ when its own repo is what's being reviewed. Use before pushing a run whose diff touched the harness itself, or whenever the harness setup changes.
---

Run **Gate 6** of this project's review pipeline: harness review — the only
gate scoped to the harness configuration itself, not the application code.

## Trigger

The run covering the *last* OpenSpec task group with pending tasks, right
after `code-review` (Gate 4 + Gate 5, merged into one delegation — see that
skill) passes, whether or not the diff needed the Gate 5 section — every
group in the run is already committed by this point (`opsx-apply-git` §3),
so this runs once per run, not once per group. Also gated by a 0-token
precondition in `opsx-apply-git` §4 step 3 (cost-optimization #35): this
delegation only runs at all if that run's diff touched
`CLAUDE.md`/`AGENTS.md`/`.claude/`/`.husky/`/`openspec/config.yaml`, or
`package.json`'s scripts/dependencies changed. Most runs touch none of them
and skip this delegation entirely.

## Action

Read `.claude/harness.json`'s `models.harness` key (written by
`init-harness`) and pass it as the `model` parameter when delegating to the
`harness-reviewer` subagent (`Agent` tool) — overriding the agent's own
frontmatter default for this run. If the manifest or the key is missing,
fall back to the agent's own default; never block the gate on a missing
override. Scope the review to the
paths `init-harness` actually writes into a target repo — `CLAUDE.md`/
`AGENTS.md`, `.claude/harness.json`, `.claude/settings.json`,
`.claude/docs/**`, `.husky/**`, `openspec/config.yaml` — plus
`${CLAUDE_PLUGIN_ROOT}/skills/` and
`${CLAUDE_PLUGIN_ROOT}/agents/` only when this plugin's own repo is the one
under review (those two directories live inside the plugin itself; a project
that has merely installed the plugin has no local copy of them to scan).
`${CLAUDE_PLUGIN_ROOT}/.claude-plugin/plugin.json` is also in scope — it is
the other half of checklist item 6's version comparison, and reading it is
how the reviewer tells "the plugin was updated but this repo wasn't" from
"up to date". That comparison needs both halves, so it doesn't run when the
repo under review has no `.claude/harness.json` of its own (this plugin's
own repo, for one); the agent reports that it couldn't run rather than
reporting a match. One check runs outside that scope on purpose: whether the
repo root has at least one continuous-build file at all (checklist item 10)
— a presence check only, not a path `init-harness` writes or owns.
Name the change so the reviewer can check for anything the change's
implementation should have updated in the harness but didn't — including
whether `.claude/harness.json` still matches reality (e.g. a new script
name, a changed coverage threshold, a package-manager switch) and whether
any skill has grown its own stack re-detection instead of reading that
manifest.

## This gate does not follow the CONFIRMED/PLAUSIBLE pause rule

Harness-review's purpose is suggesting actionable fixes, not just flagging
risk — every finding, either verdict, is shown to the user with its
suggested fix, and the user chooses what to apply. Nothing is silently
auto-applied.

- **A finding the user approves** — apply the fix and commit it as its own
  commit on the run's branch (`chore: harness review — <summary>`). Every
  group in the run is already committed by this point, so there's no
  ordering constraint forcing this ahead of a group's own commit — it
  simply lands as the next commit before push.
- **Clean, or the user declines every suggestion** — proceed straight to
  push.

## Log this gate's run

After the outcome above, append one line to `.claude/harness-log.jsonl` in
the target repo (create the file if it doesn't exist yet) — a plain shell
append, 0 model tokens:

```bash
mkdir -p .claude
printf '%s\n' "$(jq -nc \
  --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" \
  --arg group "-" \
  --arg gate "harness-review" \
  --arg verdict "<clean|plausible|confirmed>" \
  --arg skipReason "" \
  --argjson durationMs <elapsed-ms> \
  --argjson tokensTotal <subagent_tokens from the <usage> block> \
  --arg model "<model harness-reviewer actually ran on>" \
  --arg reviewConfidence "<high|low, from harness-reviewer's own Output>" \
  --argjson fixIterations 0 \
  --argjson escalatedToHuman false \
  '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,model:$model,reviewConfidence:$reviewConfidence,fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman}')" \
  >> .claude/harness-log.jsonl
```

Fill in the change slug, the verdict this run resolved to (`confirmed` if
any finding was raised regardless of whether the user chose to apply it),
the wall-clock time spent, the model `harness-reviewer` ran on (`group`
is `-`: this gate runs at change scope), and its stated `reviewConfidence`.
`skipReason` is always empty on this line — this agent's own line never
logs `verdict: "skipped"` (see the fourth-value note below for the line
that does). `tokensTotal` is the `subagent_tokens` figure from the
`<usage>` block the environment appends after the `harness-reviewer`
delegation returns (see `harness-audit/v0.4.0-implemented/03-log-fields.txt`
point 5) — never estimate this from `durationMs` or any other proxy; if
that block is absent, write `0` and say so in the report rather than
guessing.
`fixIterations`/`escalatedToHuman` are always `0`/`false` here, literally —
never computed — because an approved finding here is applied directly and
committed (see above), not run through `debug-loop`'s bounded retry cycle.
A fourth verdict value,
`skipped`, also appears under `"gate":"harness-review"` in this log — but
is written by `opsx-apply-git` itself, not by this agent, when its Gate 6
precondition finds nothing to review and this delegation never runs at all
(cost-optimization #35); that line carries `skipReason:"настройки плагина
не менялись"`, `durationMs:0`, and `tokensTotal:0`, since nothing ran. If
`jq` isn't available, construct the equivalent
JSON line with `printf` instead. A failed log write never
blocks the gate — note it in the report and move on; this is a diagnostic
aid, not part of the pass/fail logic.

## Baseline staleness — this plugin's own repo only

An eval baseline is a measurement of skill descriptions as they were on one
commit. Edit a description afterwards and the baseline keeps answering for
text that no longer exists — silently, since nothing re-runs on its own. This
gate already fires whenever the harness itself changed, which makes it the
one place that reliably notices. A plain `git` comparison, no model call:

```bash
if ls evals/baseline/*.meta >/dev/null 2>&1; then
  meta="$(ls -t evals/baseline/*.meta | head -n 1)"
  taken="$(sed -n 's/^commit:[[:space:]]*//p' "$meta")"
  moved="$(git log -1 --format=%H -- 'skills/*/SKILL.md' 'agents/*.md')"
  if [ -n "$taken" ] && [ -n "$moved" ] && [ "$taken" != "$moved" ] \
     && ! git merge-base --is-ancestor "$moved" "$taken" 2>/dev/null; then
    printf 'eval baseline %s was taken at %s, before the last edit to a skill or agent description (%s) — retake it before comparing anything against it.\n' \
      "$(basename "$meta")" "$taken" "$moved"
  fi
fi
```

Report it and move on. It blocks nothing, applies nowhere but this plugin's
own repository (no other repo has an `evals/`), and stays quiet when there is
no baseline yet.

## Stats digest

Right after this gate's own log line is written (whether this run actually
delegated to `harness-reviewer` or `opsx-apply-git` wrote a `skipped` line
for it), print one line summarizing the whole log so far — not just this
run — since Gate 6 is the one gate that reliably runs whenever the harness
itself changed, and that makes it the natural place for this to surface
without asking for it separately:

```bash
if [ -s .claude/harness-log.jsonl ] && command -v jq >/dev/null 2>&1; then
  # `fromjson?` drops any line that isn't valid JSON instead of one bad line
  # aborting the whole slurp with a parse error.
  jq -R 'fromjson?' .claude/harness-log.jsonl | jq -s -r '
    (map(select(.kind != "finding"))) as $runs |
    ((([$runs[] | select(.verdict=="skipped")] | length) / ($runs | length) * 100 * 10 | round) / 10) as $skippedPct |
    ([$runs[] | select(.escalatedToHuman == true)] | length) as $esc |
    "harness-stats: \($skippedPct)% of all logged gate runs skipped by 0-token prefilters, \($esc) escalation(s) to human. Full breakdown: references/harness-stats.md."
  '
fi
```

(python3/node equivalent if `jq` isn't available, same fallback pattern as
the rest of this plugin.) This is deliberately narrow — just the two numbers
worth seeing without asking. For the full breakdown (per-gate verdicts,
duration, `fixIterations` distribution, `reviewConfidence`, VCR, Rebuild
Cost), follow `references/harness-stats.md` — on demand, or as the
before/after measurement in the monthly harness-diet ritual (`README.md`,
#U16). No model calls anywhere in either path; it's a plain read of a JSONL
file, never worth spending tokens to compute.
