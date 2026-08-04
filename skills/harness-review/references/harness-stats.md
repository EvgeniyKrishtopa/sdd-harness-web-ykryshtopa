# `harness-stats` — reading the log nobody was reading

`.claude/harness-log.jsonl` (written by all six gates and both skip-forms
in `opsx-apply-git`, see each gate's own `## Log` section and #U13) is
appended to on every run. Until this file existed, nothing ever read it
back. This is that read path: one deterministic snippet, callable on demand
or as part of the monthly harness-diet ritual (`README.md`'s
"Harness diet" section, #U16).

## When to run this

- On demand, whenever someone asks "how's the harness doing" / "what's our
  fix-loop rate" / "how much are we skipping".
- As the "before" and "after" measurement in the harness-diet ritual (skip
  one gate's delegation, or downgrade one gate's model via `.claude/
  harness.json`'s `models.*`, for a month, run this before and after,
  compare).
- Gate 6 (`harness-review`) prints a one-line digest of just the skipped
  fraction and escalation count every time it runs — see that skill's own
  `## Stats digest` section. This file is the full version of that number.

## Why no model calls

Every metric below comes from three deterministic sources: a JSONL log, a
flat progress file, and a markdown checklist. None of them need a model to
read. Spawning a subagent (or even just asking the calling model to "look at
the log and summarize") to compute a cost metric would make the
measurement itself the largest line item it reports on — so this snippet is
plain shell, `jq` first, `python3`/`node` fallback if `jq` isn't installed,
matching the fallback chain this plugin's own `hooks/hooks.json` already
uses for JSON parsing.

## What it computes

1. **Runs and verdict distribution per gate** — how many times each of the
   six gates ran, broken down by verdict (`clean`/`plausible`/`confirmed`/
   `skipped`).
2. **Skipped fraction per gate** — the whole reason `opsx-apply-git`'s
   0-token prefilters (#35 trivial-diff, #36 Gate 6 precondition) exist is
   to skip delegations that would come back clean anyway. This is the
   number that says whether they're working.
3. **`durationMs` sum and median per gate** — total and typical wall-clock
   cost per gate.
4. **`fixIterations` distribution and `escalatedToHuman` count** — how many
   runs needed 0/1/2/... `debug-loop` attempts, and how many exhausted
   `maxFixAttempts` and stopped for a human instead.
5. **Share of `reviewConfidence: low`** — across every rated line (empty
   values, e.g. skip-forms, excluded from both sides of that ratio).
6. **VCR (Verified Completion Rate)** — `passing ÷ (passing + blocked)` from
   the *current* change's `tasks.md`, per `git-conventions.md`'s definition:
   `- [x]` lines are the passing set (the numerator); `blocked` tasks — the
   ones marked with `- [ ]` plus a `<!-- blocked: ... -->` marker on the
   same line (see `debug-loop`'s Escalate section — the checkbox is
   reverted to unchecked before the marker is written) — join passing tasks
   in the denominator. Tasks never started (`- [ ]`, no marker) count in
   neither the numerator nor the denominator. This reads `tasks.md`
   directly, not the log — the log has no per-task granularity.
7. **Rebuild Cost** — wall-clock time from the most recent `Clock-in:` line
   in `PROGRESS.md`'s `## Session log` section to the first gate run logged
   *after* that timestamp with a real pass (`verdict` is neither
   `"confirmed"` nor `"skipped"` — i.e. the first gate that actually
   completed and didn't fail, not the first log line of any kind). This is
   the "how long from resuming a session to green again" number the
   continuity work (#U3) exists to shrink.

## Empty or missing log

If `.claude/harness-log.jsonl` doesn't exist or is empty, say so in one
line and stop — VCR still runs on its own since it doesn't depend on the
log. Never let a missing log surface as a shell trace (`No such file or
directory`, a `jq` parse error) — that reads as a bug, not as "nothing's
been logged yet."

## The snippet

```bash
#!/bin/sh
# harness-stats: 0-token summary of .claude/harness-log.jsonl, PROGRESS.md,
# and the current change's tasks.md. No model calls anywhere in this path.
LOG=".claude/harness-log.jsonl"

echo "=== VCR (Verified Completion Rate) ==="
if [ -f PROGRESS.md ]; then
  change=$(awk '/^## Current change$/{f=1;next} /^## /{f=0} f && /^- Change:/{sub(/^- Change: */,""); print; exit}' PROGRESS.md)
  tasks_file="openspec/changes/${change}/tasks.md"
  if [ -n "$change" ] && [ "$change" != "none" ] && [ -f "$tasks_file" ]; then
    passing=$(grep -cE '^- \[x\]' "$tasks_file")
    blocked=$(grep -cE '^- \[ \].*<!-- blocked:' "$tasks_file")
    denom=$((passing + blocked))
    if [ "$denom" -gt 0 ]; then
      vcr=$(awk -v p="$passing" -v d="$denom" 'BEGIN{printf "%.2f", p/d}')
      echo "  $change: $passing passing / $denom started = $vcr"
    else
      echo "  $change: no started tasks yet (nothing checked off, nothing blocked)"
    fi
  else
    echo "  no current change in PROGRESS.md, or its tasks.md isn't at the expected path — skipping"
  fi
else
  echo "  no PROGRESS.md in this repo — skipping (pre-#U3 repository, or init-harness hasn't run in update mode yet)"
fi
echo

if [ ! -f "$LOG" ] || [ ! -s "$LOG" ]; then
  echo "harness-stats: $LOG is missing or empty — no gate-run stats to show yet. Run a change through opsx-apply-git first."
  exit 0
fi

# Most recent Clock-in in PROGRESS.md's Session log section, for Rebuild Cost.
clockin=""
if [ -f PROGRESS.md ]; then
  clockin=$(awk '/^## Session log$/{f=1;next} /^## /{f=0} f && /Clock-in:/{ln=$0} END{print ln}' PROGRESS.md \
    | sed -n 's/.*Clock-in: *\([0-9T:.Z-]*\).*/\1/p')
fi

echo "=== Gates, fix loop, review confidence, Rebuild Cost ==="
if command -v jq >/dev/null 2>&1; then
  # Two-stage: `fromjson?` drops any line that isn't valid JSON (a partial
  # write from a killed process, say) instead of one bad line aborting the
  # whole slurp with a parse error — the python3/node branches below already
  # skip bad lines the same way, via their own try/except and try/catch.
  jq -R 'fromjson?' "$LOG" | jq -s -r --arg since "$clockin" '
    (group_by(.gate)[] | {
      gate: .[0].gate, runs: length,
      verdicts: (group_by(.verdict) | map("\(.[0].verdict)=\(length)") | join(", ")),
      skippedPct: ((([.[] | select(.verdict=="skipped")] | length) / length * 100 * 10 | round) / 10),
      durSumMs: ([.[] | (.durationMs // 0)] | add),
      durMedianMs: ([.[] | (.durationMs // 0)] | sort |
        (if (length % 2) == 1 then .[(length-1)/2] else (.[length/2 - 1] + .[length/2]) / 2 end))
    } | "  \(.gate): \(.runs) runs (\(.verdicts)) — \(.skippedPct)% skipped, durationMs sum=\(.durSumMs) median=\(.durMedianMs)"),
    "",
    ((group_by(.fixIterations // 0) | map("\(.[0].fixIterations // 0) attempt(s): \(length) run(s)") | join("; ")) as $dist |
      ([.[] | select(.escalatedToHuman == true)] | length) as $esc |
      "  fixIterations distribution: \($dist)\n  escalatedToHuman=true: \($esc) run(s)"),
    "",
    (([.[] | select(.reviewConfidence == "low" or .reviewConfidence == "high")]) as $rated |
      if ($rated | length) == 0 then "  reviewConfidence: no rated reviews yet"
      else "  reviewConfidence: \((([$rated[] | select(.reviewConfidence == "low")] | length) / ($rated | length) * 100 * 10 | round) / 10)% low (\($rated | length) rated)"
      end),
    "",
    (if ($since // "") == "" then "  Rebuild Cost: no Clock-in found in PROGRESS.md — skipping"
     else
       ([.[] | select(.ts > $since and .verdict != "confirmed" and .verdict != "skipped")] | sort_by(.ts) | .[0].ts // "") as $firstPass |
       if $firstPass == "" then "  Rebuild Cost: clock-in \($since), no passed gate logged after it yet"
       else "  Rebuild Cost: clock-in \($since) -> first passed gate \($firstPass)"
       end
     end)
  '
elif command -v python3 >/dev/null 2>&1; then
  python3 - "$LOG" "$clockin" <<'PY'
import json, sys, statistics
from collections import defaultdict

log_path, since = sys.argv[1], sys.argv[2]
rows = []
with open(log_path) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue

by_gate = defaultdict(list)
for r in rows:
    by_gate[r.get("gate", "?")].append(r)
for gate in sorted(by_gate):
    entries = by_gate[gate]
    verdicts = defaultdict(int)
    for e in entries:
        verdicts[e.get("verdict", "?")] += 1
    verdict_str = ", ".join(f"{k}={v}" for k, v in sorted(verdicts.items()))
    skipped_pct = round(100 * verdicts.get("skipped", 0) / len(entries), 1)
    durations = [e.get("durationMs", 0) or 0 for e in entries]
    print(f"  {gate}: {len(entries)} runs ({verdict_str}) — {skipped_pct}% skipped, "
          f"durationMs sum={sum(durations)} median={statistics.median(durations) if durations else 0}")

print()
fix_dist = defaultdict(int)
escalations = 0
for r in rows:
    fix_dist[r.get("fixIterations", 0) or 0] += 1
    if r.get("escalatedToHuman") is True:
        escalations += 1
dist_str = "; ".join(f"{k} attempt(s): {v} run(s)" for k, v in sorted(fix_dist.items()))
print(f"  fixIterations distribution: {dist_str}")
print(f"  escalatedToHuman=true: {escalations} run(s)")

print()
rated = [r for r in rows if r.get("reviewConfidence") in ("low", "high")]
if not rated:
    print("  reviewConfidence: no rated reviews yet")
else:
    low_pct = round(100 * sum(1 for r in rated if r["reviewConfidence"] == "low") / len(rated), 1)
    print(f"  reviewConfidence: {low_pct}% low ({len(rated)} rated)")

print()
if not since:
    print("  Rebuild Cost: no Clock-in found in PROGRESS.md — skipping")
else:
    passed_after = sorted(
        (r["ts"] for r in rows if r.get("ts", "") > since and r.get("verdict") not in ("confirmed", "skipped"))
    )
    if not passed_after:
        print(f"  Rebuild Cost: clock-in {since}, no passed gate logged after it yet")
    else:
        print(f"  Rebuild Cost: clock-in {since} -> first passed gate {passed_after[0]}")
PY
elif command -v node >/dev/null 2>&1; then
  node - "$LOG" "$clockin" <<'JS'
const fs = require('fs');
const [logPath, since] = process.argv.slice(2);
const rows = fs.readFileSync(logPath, 'utf8').split('\n').filter(Boolean).map(l => {
  try { return JSON.parse(l); } catch { return null; }
}).filter(Boolean);

const byGate = {};
for (const r of rows) (byGate[r.gate] ||= []).push(r);
for (const gate of Object.keys(byGate).sort()) {
  const entries = byGate[gate];
  const verdicts = {};
  for (const e of entries) verdicts[e.verdict] = (verdicts[e.verdict] || 0) + 1;
  const verdictStr = Object.keys(verdicts).sort().map(k => `${k}=${verdicts[k]}`).join(', ');
  const skippedPct = Math.round((100 * (verdicts.skipped || 0) / entries.length) * 10) / 10;
  const durations = entries.map(e => e.durationMs || 0).sort((a, b) => a - b);
  const sum = durations.reduce((a, b) => a + b, 0);
  const mid = Math.floor(durations.length / 2);
  const median = durations.length === 0 ? 0 : (durations.length % 2 ? durations[mid] : (durations[mid - 1] + durations[mid]) / 2);
  console.log(`  ${gate}: ${entries.length} runs (${verdictStr}) — ${skippedPct}% skipped, durationMs sum=${sum} median=${median}`);
}

console.log();
const fixDist = {};
let escalations = 0;
for (const r of rows) {
  const fi = r.fixIterations || 0;
  fixDist[fi] = (fixDist[fi] || 0) + 1;
  if (r.escalatedToHuman === true) escalations++;
}
const distStr = Object.keys(fixDist).sort((a, b) => a - b).map(k => `${k} attempt(s): ${fixDist[k]} run(s)`).join('; ');
console.log(`  fixIterations distribution: ${distStr}`);
console.log(`  escalatedToHuman=true: ${escalations} run(s)`);

console.log();
const rated = rows.filter(r => r.reviewConfidence === 'low' || r.reviewConfidence === 'high');
if (rated.length === 0) {
  console.log('  reviewConfidence: no rated reviews yet');
} else {
  const lowPct = Math.round((100 * rated.filter(r => r.reviewConfidence === 'low').length / rated.length) * 10) / 10;
  console.log(`  reviewConfidence: ${lowPct}% low (${rated.length} rated)`);
}

console.log();
if (!since) {
  console.log('  Rebuild Cost: no Clock-in found in PROGRESS.md — skipping');
} else {
  const passedAfter = rows.filter(r => (r.ts || '') > since && r.verdict !== 'confirmed' && r.verdict !== 'skipped')
    .map(r => r.ts).sort();
  if (passedAfter.length === 0) {
    console.log(`  Rebuild Cost: clock-in ${since}, no passed gate logged after it yet`);
  } else {
    console.log(`  Rebuild Cost: clock-in ${since} -> first passed gate ${passedAfter[0]}`);
  }
}
JS
else
  echo "harness-stats: none of jq, python3, node is available — cannot compute gate stats deterministically."
fi
```

ISO-8601 UTC timestamps (`ts` in the log, `Clock-in:` in `PROGRESS.md`) sort
and compare correctly as plain strings — no date parsing needed for the
Rebuild Cost comparison in any of the three branches.
