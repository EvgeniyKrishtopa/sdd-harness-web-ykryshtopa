#!/usr/bin/env bash
# Smoke test for this plugin's JSON manifests and markdown frontmatter.
#
# Catches the class of bug that reached commit e57b8ad unnoticed: #1 (
# hooks/hooks.json missing its top-level "hooks" wrapper) and #21 (.mcp.json
# not matching a shape Claude Code actually loads) were both silent,
# structurally-wrong JSON that no one ran the plugin against a real repo to
# catch. Note on #21: the two shapes are not right-and-wrong. Every official
# plugin in claude-plugins-official puts servers at the top level, while the
# plugin reference documents the "mcpServers" wrapper; both load, so this
# script checks that the servers themselves are launchable rather than
# policing which wrapper is used. This script needs nothing
# beyond a POSIX shell — jq is used if present, with a python3 or node
# fallback, and a degraded grep-based check if none of the three exist.
#
# Run from anywhere:
#   bash tests/smoke-json-schema.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT" || exit 1

pass_count=0
fail_count=0
warn_count=0

ok()   { printf '  [OK]   %s\n' "$1"; pass_count=$((pass_count + 1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; fail_count=$((fail_count + 1)); }
note() { printf '  [WARN] %s\n' "$1"; warn_count=$((warn_count + 1)); }

echo "== sdd-harness-web-ykryshtopa :: JSON schema + frontmatter smoke test =="
echo "Repo root: $ROOT"

if command -v jq >/dev/null 2>&1; then
  ENGINE=jq
elif command -v python3 >/dev/null 2>&1; then
  ENGINE=python3
elif command -v node >/dev/null 2>&1; then
  ENGINE=node
else
  ENGINE=none
fi
echo "JSON engine: $ENGINE"
if [ "$ENGINE" = none ]; then
  note "no jq, python3, or node found on PATH — JSON checks degrade to a crude grep-based sanity check that cannot fully validate syntax or shape"
fi
echo

# --- JSON helpers, one implementation per available engine -----------------

json_valid() {
  f="$1"
  case "$ENGINE" in
    jq) jq empty "$f" >/dev/null 2>&1 ;;
    python3) python3 -c 'import json,sys; json.load(open(sys.argv[1]))' "$f" >/dev/null 2>&1 ;;
    node) node -e 'JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"))' "$f" >/dev/null 2>&1 ;;
    none) [ -s "$f" ] && head -c 1 "$f" | grep -q '[{[]' ;;
  esac
}

json_has_top_key() {
  f="$1"; key="$2"
  case "$ENGINE" in
    jq) jq -e --arg k "$key" 'has($k)' "$f" >/dev/null 2>&1 ;;
    python3) python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if isinstance(d, dict) and sys.argv[2] in d else 1)
' "$f" "$key" ;;
    node) node -e '
const d = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
process.exit(d && typeof d === "object" && Object.prototype.hasOwnProperty.call(d, process.argv[2]) ? 0 : 1);
' "$f" "$key" ;;
    none) grep -qE "\"$key\"[[:space:]]*:" "$f" ;;
  esac
}

# Print a top-level string field, or nothing when absent.
json_str() {
  f="$1"; key="$2"
  case "$ENGINE" in
    jq) jq -r --arg k "$key" '.[$k] // "" | tostring' "$f" 2>/dev/null ;;
    python3) python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
v = d.get(sys.argv[2]) if isinstance(d, dict) else None
print("" if v is None else v)
' "$f" "$key" 2>/dev/null ;;
    node) node -e '
const d = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const v = d && typeof d === "object" ? d[process.argv[2]] : undefined;
process.stdout.write(v === undefined || v === null ? "" : String(v));
' "$f" "$key" 2>/dev/null ;;
    none) sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$f" | head -1 ;;
  esac
}

# Print a string field of the first entry in plugins[], or nothing.
json_plugin0_str() {
  f="$1"; key="$2"
  case "$ENGINE" in
    jq) jq -r --arg k "$key" '(.plugins[0][$k] // "") | tostring' "$f" 2>/dev/null ;;
    python3) python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
p = (d.get("plugins") or [{}])[0]
v = p.get(sys.argv[2]) if isinstance(p, dict) else None
print("" if v is None else v)
' "$f" "$key" 2>/dev/null ;;
    node) node -e '
const d = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const p = (d.plugins || [{}])[0] || {};
const v = p[process.argv[2]];
process.stdout.write(v === undefined || v === null ? "" : String(v));
' "$f" "$key" 2>/dev/null ;;
    none) sed -n "s/.*\"$key\"[[:space:]]*:[[:space:]]*\"\([^\"]*\)\".*/\1/p" "$f" | head -1 ;;
  esac
}

json_lacks_top_key() {
  f="$1"; key="$2"
  if json_has_top_key "$f" "$key"; then
    return 1
  else
    return 0
  fi
}

# Every declared MCP server must be launchable: a stdio server has a
# "command", an http/sse one has a "url". Servers live either at the top
# level (the form every official plugin in claude-plugins-official ships) or
# under an "mcpServers" wrapper (the form the plugin reference documents) —
# Claude Code reads both, so this accepts both and only checks the entries.
mcp_entries_launchable() {
  f="$1"
  case "$ENGINE" in
    jq) jq -e '(if has("mcpServers") then .mcpServers else . end) | (to_entries | length) > 0 and (to_entries | all(.value | (has("command") or has("url"))))' "$f" >/dev/null 2>&1 ;;
    python3) python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
if isinstance(d, dict) and "mcpServers" in d:
    d = d["mcpServers"]
sys.exit(0 if isinstance(d, dict) and len(d) > 0 and all(isinstance(v, dict) and ("command" in v or "url" in v) for v in d.values()) else 1)
' "$f" ;;
    node) node -e '
let d = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
if (d && typeof d === "object" && d.mcpServers) d = d.mcpServers;
const vals = Object.values(d || {});
process.exit(vals.length > 0 && vals.every(v => v && typeof v === "object" && ("command" in v || "url" in v)) ? 0 : 1);
' "$f" ;;
    none) grep -qE '"(command|url)"' "$f" ;;
  esac
}

marketplace_plugins_shape_ok() {
  f="$1"
  case "$ENGINE" in
    jq) jq -e '(.plugins | type) == "array" and (.plugins | length) > 0 and (.plugins | all(has("name") and has("source")))' "$f" >/dev/null 2>&1 ;;
    python3) python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get("plugins")
sys.exit(0 if isinstance(p, list) and len(p) > 0 and all(isinstance(x, dict) and "name" in x and "source" in x for x in p) else 1)
' "$f" ;;
    node) node -e '
const d = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const p = d.plugins;
process.exit(Array.isArray(p) && p.length > 0 && p.every(x => x && typeof x === "object" && "name" in x && "source" in x) ? 0 : 1);
' "$f" ;;
    none) grep -q '"plugins"' "$f" && grep -q '"source"' "$f" ;;
  esac
}

# --- Checks 1 & 2: JSON syntax + shape --------------------------------------

echo "-- JSON syntax --"
for f in .claude-plugin/plugin.json .claude-plugin/marketplace.json hooks/hooks.json .mcp.json; do
  if [ ! -f "$f" ]; then
    bad "$f does not exist"
    continue
  fi
  if json_valid "$f"; then
    ok "$f is valid JSON"
  else
    bad "$f is not valid JSON"
  fi
done
echo

echo "-- JSON shape --"

# #1: hooks.json must have a top-level "hooks" key, not be the bare
# {"PreToolUse": [...]} shape that broke the whole hook layer.
if [ -f hooks/hooks.json ] && json_valid hooks/hooks.json; then
  if json_has_top_key hooks/hooks.json hooks; then
    ok 'hooks/hooks.json has top-level "hooks" key'
  else
    bad 'hooks/hooks.json is MISSING the top-level "hooks" key (this is #1 — the hook layer silently never loads)'
  fi
fi

if [ -f .claude-plugin/plugin.json ] && json_valid .claude-plugin/plugin.json; then
  missing=""
  for key in name version description; do
    json_has_top_key .claude-plugin/plugin.json "$key" || missing="$missing $key"
  done
  if [ -z "$missing" ]; then
    ok ".claude-plugin/plugin.json has name, version, description"
  else
    bad ".claude-plugin/plugin.json is missing key(s):$missing"
  fi
fi

# A declared version pins installs: Claude Code caches by resolved version
# and skips a plugin whose version it already has, so a release pushed
# without a bump reaches nobody. These three checks make the release rule
# from the README enforceable rather than remembered.
if [ -f .claude-plugin/plugin.json ] && json_valid .claude-plugin/plugin.json; then
  ver="$(json_str .claude-plugin/plugin.json version)"
  if printf '%s' "$ver" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
    ok "plugin.json version \"$ver\" is semver"
  else
    bad "plugin.json version \"$ver\" is not semver (major.minor.patch)"
  fi

  if [ -f .claude-plugin/marketplace.json ] && json_valid .claude-plugin/marketplace.json; then
    if [ -n "$(json_plugin0_str .claude-plugin/marketplace.json version)" ]; then
      bad 'the marketplace entry also declares a "version" — Claude Code silently prefers plugin.json, so a stale manifest would mask it. Keep the version in plugin.json only'
    else
      ok 'the marketplace entry leaves "version" to plugin.json (no competing value)'
    fi
  fi

  if [ -f CHANGELOG.md ]; then
    if grep -qE "^##[[:space:]]+v?${ver}([[:space:]]|$)" CHANGELOG.md; then
      ok "CHANGELOG.md has a section for $ver"
    else
      bad "CHANGELOG.md has no \"## $ver\" section — bump and changelog entry go together"
    fi
  else
    bad "CHANGELOG.md does not exist, so no release is documented"
  fi
fi

if [ -f .claude-plugin/marketplace.json ] && json_valid .claude-plugin/marketplace.json; then
  missing=""
  for key in name owner plugins; do
    json_has_top_key .claude-plugin/marketplace.json "$key" || missing="$missing $key"
  done
  if [ -n "$missing" ]; then
    bad ".claude-plugin/marketplace.json is missing key(s):$missing"
  elif marketplace_plugins_shape_ok .claude-plugin/marketplace.json; then
    ok ".claude-plugin/marketplace.json has name, owner, and a non-empty plugins[] with name+source"
  else
    bad ".claude-plugin/marketplace.json's plugins[] entries are missing name/source, or plugins is empty/not an array"
  fi
fi

# #21: .mcp.json must declare at least one launchable server, in either of
# the two shapes Claude Code accepts (see mcp_entries_launchable above).
if [ -f .mcp.json ] && json_valid .mcp.json; then
  if json_lacks_top_key .mcp.json mcpServers; then
    shape='servers as top-level keys (the shipped-plugin form)'
  else
    shape='servers under an "mcpServers" wrapper (the documented form)'
  fi
  if mcp_entries_launchable .mcp.json; then
    ok ".mcp.json declares $shape, each with a \"command\" or \"url\""
  else
    bad ".mcp.json has $shape but an entry is missing both \"command\" and \"url\", or there are no servers at all"
  fi
fi
echo

# --- Check 3: frontmatter ----------------------------------------------------

echo "-- Frontmatter --"

# Print the lines strictly between the file's first "---" and the next "---".
# Prints nothing if the frontmatter is never closed by a second "---" —
# an unterminated block is not valid frontmatter, not a pass.
extract_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { closed = 1; exit }
    infm { buf[n++] = $0 }
    END { if (closed) for (i = 0; i < n; i++) print buf[i] }
  ' "$1"
}

check_frontmatter() {
  file="$1"; shift
  fm="$(extract_frontmatter "$file")"
  if [ -z "$fm" ]; then
    bad "$file has no YAML frontmatter (must start with a --- line)"
    return
  fi
  missing=""
  for field in "$@"; do
    printf '%s\n' "$fm" | grep -qE "^${field}:" || missing="$missing $field"
  done
  if [ -n "$missing" ]; then
    bad "$file frontmatter is missing field(s):$missing"
  else
    ok "$file frontmatter has: $*"
  fi
}

shopt -s nullglob 2>/dev/null || true

for f in skills/*/SKILL.md; do
  check_frontmatter "$f" name description
done

for f in agents/*.md; do
  check_frontmatter "$f" name description tools model
done

# A field's presence isn't enough: the block has to be parseable YAML. An
# unquoted plain scalar containing ": " (e.g. `description: ... <example>
# Context: ...`) makes YAML read a nested mapping key and the whole
# frontmatter fails — at which point every field is dropped and a
# "read-only" agent silently inherits the full tool set. Quote such a value
# or make it a folded block scalar (`>-`), as the agents here do.
check_frontmatter_parseable() {
  file="$1"
  offenders="$(extract_frontmatter "$file" | awk '
    /^[A-Za-z_-]+:[[:space:]]/ {
      key = $0; sub(/:.*/, "", key)
      val = $0; sub(/^[A-Za-z_-]+:[[:space:]]+/, "", val)
      first = substr(val, 1, 1)
      if (first == ">" || first == "|" || first == "\"" || first == "'"'"'") next
      if (val ~ /: /) print key
    }')"
  if [ -n "$offenders" ]; then
    bad "$file frontmatter would fail to parse as YAML — unquoted value(s) containing \": \" in field(s): $(printf '%s' "$offenders" | tr '\n' ' ')"
  else
    ok "$file frontmatter is YAML-parseable (no unquoted \": \" in a plain scalar)"
  fi
}

for f in skills/*/SKILL.md agents/*.md; do
  check_frontmatter_parseable "$f"
done
echo

# --- Check: instruction length (V-4) ----------------------------------------

echo "-- Instruction length --"

# A hard 250-line cap would go red immediately on two instructions that
# already passed it before this rule existed, and the workflow requires a
# green test before merging any session -- so a flat cap would drag "split
# up two large instructions" into this change uninvited. Grandfathering
# today's size as a per-file ceiling avoids that: no file may grow, but
# nothing has to be split right now either. See
# harness-audit/v0.4.0-implemented/05-design-rationale.txt, decision 8.
# Ratchet: whenever one of these files is split, its cap tightens to the new
# size in the same commit. 0.4.1 moved the conditional and reference-shaped
# parts of both into references/ (init-harness 838 -> 408, opsx-apply-git
# 475 -> 433), so the old ceilings would have left room to grow straight back
# into the size the split just removed.
SKILL_LINE_CAP=250
grandfathered_skill_cap() {
  case "$1" in
    init-harness) echo 408 ;;
    opsx-apply-git) echo 433 ;;
    *) echo "" ;;
  esac
}

for f in skills/*/SKILL.md; do
  skill_name="$(basename "$(dirname "$f")")"
  lines="$(wc -l < "$f" | tr -d ' ')"
  cap="$(grandfathered_skill_cap "$skill_name")"
  if [ -n "$cap" ]; then
    if [ "$lines" -le "$cap" ]; then
      ok "$f is $lines lines (grandfathered cap: $cap)"
    else
      bad "$f grew to $lines lines, past its grandfathered cap of $cap lines"
    fi
  else
    if [ "$lines" -le "$SKILL_LINE_CAP" ]; then
      ok "$f is $lines lines (limit: $SKILL_LINE_CAP)"
    else
      bad "$f is $lines lines, over the $SKILL_LINE_CAP-line limit"
    fi
  fi
done
echo

# --- Check for 0.3.0 surfaces (#U17) ----------------------------------------

echo "-- 0.3.0 surfaces --"

# harnessVersion's documented example in init-harness Step 8 must be
# semver-shaped, the same shape plugin.json's own "version" is checked
# against above. The SKILL.md text is explicit that the example value itself
# ("0.3.0") is "the shape, not a constant to copy" -- so this checks form,
# not equality with plugin.json.
INIT_SKILL="skills/init-harness/SKILL.md"
# The manifest example moved out of SKILL.md into this reference when Step 8
# was split for progressive disclosure. The checks below follow the content,
# not the filename: what matters is that the example a run copies from is
# semver-shaped and still names the keys later releases added.
MANIFEST_REF="skills/init-harness/references/manifest-schema.md"
if [ ! -f "$INIT_SKILL" ]; then
  bad "$INIT_SKILL does not exist"
elif [ ! -f "$MANIFEST_REF" ]; then
  bad "$MANIFEST_REF does not exist — Step 8's manifest example has no home"
else
  example_version="$(grep -m1 '"harnessVersion":' "$MANIFEST_REF" | sed -E 's/.*"harnessVersion":[[:space:]]*"([^"]*)".*/\1/')"
  if printf '%s' "$example_version" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+([-+][0-9A-Za-z.-]+)?$'; then
    ok "$MANIFEST_REF's harnessVersion example (\"$example_version\") is shaped like a semver version"
  else
    bad "$MANIFEST_REF's harnessVersion example is missing or not semver-shaped"
  fi

  if grep -q '"maxFixAttempts"' "$MANIFEST_REF" && grep -q '"toolchainVerifiedAt"' "$MANIFEST_REF"; then
    ok "$MANIFEST_REF documents maxFixAttempts and toolchainVerifiedAt in the manifest example"
  else
    bad "$MANIFEST_REF's manifest example is missing maxFixAttempts and/or toolchainVerifiedAt"
  fi
fi

# Every harness-log.jsonl line literal -- one per gate skill, plus
# opsx-apply-git's two skip forms -- must emit the exact same field set.
# This is the check that would have caught "updated five places out of
# seven" (#U13's own risk, named in the plan) instead of a human noticing a
# missing field months later while reading harness-stats output.
log_line_fields() {
  # field names only, in order, comma-joined, from one object literal line
  printf '%s\n' "$1" | grep -oE '[A-Za-z]+:' | tr -d ':' | tr '\n' ','
}

log_lines="$(grep -rn 'ts:\$ts' skills/*/SKILL.md 2>/dev/null)"
if [ -z "$log_lines" ]; then
  bad "no harness-log.jsonl line literals found under skills/*/SKILL.md"
else
  first_fields=""; first_loc=""; mismatches=""; total=0
  while IFS= read -r logline; do
    [ -z "$logline" ] && continue
    loc="$(printf '%s' "$logline" | cut -d: -f1,2)"
    content="$(printf '%s' "$logline" | cut -d: -f3-)"
    fields="$(log_line_fields "$content")"
    total=$((total + 1))
    if [ -z "$first_fields" ]; then
      first_fields="$fields"; first_loc="$loc"
    elif [ "$fields" != "$first_fields" ]; then
      mismatches="$mismatches $loc"
    fi
  done <<LOGEOF
$log_lines
LOGEOF
  if [ -n "$mismatches" ]; then
    bad "harness-log.jsonl line field set differs from $first_loc ($first_fields) at:$mismatches"
  else
    ok "all $total harness-log.jsonl line literals (every gate + opsx-apply-git's two skip forms) share the same field set"
  fi
fi

# debug-loop's description needs to name concrete trigger phrases, not just
# describe what the skill generically does -- that's what lets Claude's own
# skill-matcher and a human reader tell when to reach for it.
DEBUG_LOOP_SKILL="skills/debug-loop/SKILL.md"
if [ -f "$DEBUG_LOOP_SKILL" ]; then
  desc="$(extract_frontmatter "$DEBUG_LOOP_SKILL" | grep '^description:')"
  missing=""
  for phrase in "maxFixAttempts" "web-qa FAIL" "CONFIRMED finding"; do
    printf '%s' "$desc" | grep -qF "$phrase" || missing="$missing [$phrase]"
  done
  if [ -n "$desc" ] && [ -z "$missing" ]; then
    ok "$DEBUG_LOOP_SKILL's frontmatter description names concrete trigger phrases"
  else
    bad "$DEBUG_LOOP_SKILL's frontmatter description is missing or missing trigger phrase(s):$missing"
  fi
else
  bad "$DEBUG_LOOP_SKILL does not exist"
fi

# Every {{PLACEHOLDER}} that appears in an init-harness reference template
# must also be named in SKILL.md, which is where the substitution is
# actually instructed. The two drift in one direction only: a placeholder
# added to a template and not to the skill ships a literal "{{FRAMEWORK}}"
# into a user's repo, and nothing else in this suite would notice. Both
# defects of this shape found so far -- a Vite script name hardcoded where a
# substitution belonged, and Step 5 naming two of four placeholders -- were
# caught by reading, which is exactly the method that doesn't scale.
tmpl_missing=""
tmpl_total=0
for tmpl in skills/init-harness/references/*.md; do
  [ -f "$tmpl" ] || continue
  for ph in $(grep -o '{{[A-Z_]*}}' "$tmpl" 2>/dev/null | sort -u); do
    tmpl_total=$((tmpl_total + 1))
    grep -qF "$ph" "$INIT_SKILL" 2>/dev/null \
      || tmpl_missing="$tmpl_missing [$(basename "$tmpl"):$ph]"
  done
done
if [ "$tmpl_total" -eq 0 ]; then
  bad "no {{PLACEHOLDER}} tokens found in skills/init-harness/references/ -- did the templates move?"
elif [ -n "$tmpl_missing" ]; then
  bad "placeholder(s) in a template but never named in $INIT_SKILL:$tmpl_missing"
else
  ok "all $tmpl_total template placeholders are named in $INIT_SKILL's substitution instructions"
fi
echo

# --- Check: progressive disclosure is wired up ------------------------------

echo "-- Progressive disclosure --"

# A SKILL.md loads in full every time its skill fires; a references/ file
# loads only when the instruction says to read it. That split is only safe
# while every extracted file is actually pointed at -- an unreferenced
# reference is not "documentation kept nearby", it is an instruction that
# silently stopped running. This is the check that keeps a future extraction
# from quietly dropping a step. A file counts as reachable when its basename
# appears in its own SKILL.md or in any sibling file within the same skill
# (record-rejection.mjs, for instance, is invoked by its .sh wrapper).
unreachable=""
reachable_total=0
for skill_dir in skills/*/; do
  skill_md="${skill_dir}SKILL.md"
  [ -f "$skill_md" ] || continue
  for aux in "$skill_dir"references/* "$skill_dir"scripts/*; do
    [ -f "$aux" ] || continue
    reachable_total=$((reachable_total + 1))
    base="$(basename "$aux")"
    if grep -qF "$base" "$skill_md" 2>/dev/null; then
      continue
    fi
    # not named directly -- look for an indirect mention from a sibling
    found=""
    for sib in "$skill_dir"references/* "$skill_dir"scripts/*; do
      [ -f "$sib" ] || continue
      [ "$sib" = "$aux" ] && continue
      grep -qF "$base" "$sib" 2>/dev/null && { found=1; break; }
    done
    [ -n "$found" ] || unreachable="$unreachable [$aux]"
  done
done
if [ "$reachable_total" -eq 0 ]; then
  bad "no references/ or scripts/ files found under skills/ -- did they move?"
elif [ -n "$unreachable" ]; then
  bad "file(s) never named by their own SKILL.md or any sibling, so nothing ever reads them:$unreachable"
else
  ok "all $reachable_total references/ and scripts/ files are reachable from their SKILL.md"
fi

# Every path a SKILL.md tells the model to read has to exist. A pointer to a
# renamed or deleted reference fails silently at run time: the model reads
# nothing and continues without the step.
dangling=""
link_total=0
for skill_md in skills/*/SKILL.md; do
  skill_dir="$(dirname "$skill_md")"
  for p in $(grep -o '`\(references\|scripts\)/[A-Za-z0-9._/-]*`' "$skill_md" 2>/dev/null | tr -d '`' | sort -u); do
    link_total=$((link_total + 1))
    [ -e "$skill_dir/$p" ] || dangling="$dangling [$skill_md -> $p]"
  done
done
if [ -n "$dangling" ]; then
  bad "SKILL.md points at path(s) that do not exist:$dangling"
else
  ok "all $link_total references/ and scripts/ paths named in a SKILL.md resolve"
fi
echo

# --- Check 4: the official validator, when the CLI is available ------------

echo "-- claude plugin validate --"

if command -v claude >/dev/null 2>&1; then
  # Validate the plugin, not the marketplace: given a directory containing
  # both manifests, `claude plugin validate` checks only marketplace.json
  # and never looks at agents/ at all. Copy the plugin half out to get the
  # agent and manifest checks to actually run.
  vtmp="$(mktemp -d)"
  trap 'rm -rf "$vtmp"' EXIT
  mkdir -p "$vtmp/.claude-plugin"
  cp .claude-plugin/plugin.json "$vtmp/.claude-plugin/" 2>/dev/null
  [ -f .mcp.json ] && cp .mcp.json "$vtmp/"
  for d in agents skills hooks commands; do
    [ -d "$d" ] && cp -R "$d" "$vtmp/"
  done
  if vout="$(claude plugin validate "$vtmp" --strict 2>&1)"; then
    ok "claude plugin validate --strict passes for the plugin manifest and every agent"
  else
    bad "claude plugin validate --strict failed:"
    printf '%s\n' "$vout" | sed 's/^/         /'
  fi
  if mout="$(claude plugin validate . --strict 2>&1)"; then
    ok "claude plugin validate --strict passes for the marketplace manifest"
  else
    bad "claude plugin validate --strict failed for the marketplace manifest:"
    printf '%s\n' "$mout" | sed 's/^/         /'
  fi
else
  note "claude CLI not on PATH — skipped the official 'claude plugin validate --strict' pass, which is the authoritative check for the two above"
fi
echo

# --- Summary -----------------------------------------------------------------

echo "== Summary =="
printf '  %d passed, %d failed, %d warning(s)\n' "$pass_count" "$fail_count" "$warn_count"

if [ "$fail_count" -gt 0 ]; then
  echo "SMOKE TEST FAILED"
  exit 1
fi

echo "SMOKE TEST PASSED"
exit 0
