#!/usr/bin/env bash
# Smoke test for this plugin's JSON manifests and markdown frontmatter.
#
# Catches the class of bug that reached commit e57b8ad unnoticed: #1 (
# hooks/hooks.json missing its top-level "hooks" wrapper) and #21 (.mcp.json
# wrapped in "mcpServers" instead of matching the official plugin's
# top-level-keys form) were both silent, structurally-wrong JSON that no one
# ran the plugin against a real repo to catch. This script needs nothing
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

json_lacks_top_key() {
  f="$1"; key="$2"
  if json_has_top_key "$f" "$key"; then
    return 1
  else
    return 0
  fi
}

mcp_entries_have_command() {
  f="$1"
  case "$ENGINE" in
    jq) jq -e '(to_entries | length) > 0 and (to_entries | all(.value | has("command")))' "$f" >/dev/null 2>&1 ;;
    python3) python3 -c '
import json, sys
d = json.load(open(sys.argv[1]))
sys.exit(0 if isinstance(d, dict) and len(d) > 0 and all(isinstance(v, dict) and "command" in v for v in d.values()) else 1)
' "$f" ;;
    node) node -e '
const d = JSON.parse(require("fs").readFileSync(process.argv[1],"utf8"));
const vals = Object.values(d || {});
process.exit(vals.length > 0 && vals.every(v => v && typeof v === "object" && "command" in v) ? 0 : 1);
' "$f" ;;
    none) grep -q '"command"' "$f" ;;
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
process.exit(Array.isArray(p) && p.length > 0 && p.every(x => x && "name" in x && "source" in x) ? 0 : 1);
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

# #21: .mcp.json must have MCP servers as top-level keys (the official
# plugin form), not wrapped in an "mcpServers" object.
if [ -f .mcp.json ] && json_valid .mcp.json; then
  if json_lacks_top_key .mcp.json mcpServers; then
    if mcp_entries_have_command .mcp.json; then
      ok '.mcp.json has servers as top-level keys (not wrapped in "mcpServers"), each with a "command"'
    else
      bad '.mcp.json top-level entries are missing a "command" field, or the file has no servers'
    fi
  else
    bad '.mcp.json is wrapped in a top-level "mcpServers" key (this is #21 — official plugins put servers at the top level)'
  fi
fi
echo

# --- Check 3: frontmatter ----------------------------------------------------

echo "-- Frontmatter --"

# Print the lines strictly between the file's first "---" and the next "---".
extract_frontmatter() {
  awk '
    NR == 1 && $0 == "---" { infm = 1; next }
    infm && $0 == "---" { exit }
    infm { print }
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
