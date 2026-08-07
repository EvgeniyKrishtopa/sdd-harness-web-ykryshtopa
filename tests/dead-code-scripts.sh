#!/usr/bin/env bash
# Behaviour test for skills/dead-code-report/scripts/*.
#
# These five scripts shipped in 0.4.0 with no automated coverage at all,
# and that is exactly how the defect this file's first check pins down got
# in: verify-string-reference.sh excluded the candidate's own lines by
# filtering the whole grep output line, so a line in a DIFFERENT file that
# merely mentioned the candidate's path -- which is precisely the string
# reference the script exists to find -- was discarded along with the
# self-match. The script then reported "nothing found", which promotes a
# genuinely-referenced file to Group 1, "safe to delete". A reviewer reading
# the script agreed with it; only running it disagreed.
#
# Run from anywhere:
#   bash tests/dead-code-scripts.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPTS="$ROOT/skills/dead-code-report/scripts"

pass_count=0
fail_count=0

ok()  { printf '  [OK]   %s\n' "$1"; pass_count=$((pass_count + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail_count=$((fail_count + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== dead-code-report scripts :: behaviour test =="
echo "Repo root: $ROOT"
echo

# --- verify-string-reference.sh ---------------------------------------------

echo "-- verify-string-reference.sh --"

proj="$TMP/proj"
mkdir -p "$proj/src" "$proj/config"
echo 'export const formatPrice = (n) => n;' > "$proj/src/formatPrice.ts"
# The reference static analysis cannot see: a path inside a config string.
printf '{\n  "dynamicEntry": "src/formatPrice.ts"\n}\n' > "$proj/config/build.json"
echo 'export const orphan = 1;' > "$proj/src/orphan.ts"

out="$(bash "$SCRIPTS/verify-string-reference.sh" "src/formatPrice.ts" "$proj" 2>&1)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | grep -q 'build.json'; then
  ok 'a path referenced only as a string in another file is found (exit 0 -> downgrade to Group 3)'
else
  bad "a string-only reference was NOT found (exit $rc, output: ${out:-<empty>}) — this is the 0.4.0 defect: the file would be reported as safe to delete"
fi

out="$(bash "$SCRIPTS/verify-string-reference.sh" "src/orphan.ts" "$proj" 2>&1)"
rc=$?
if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
  ok 'a genuinely unreferenced file stays in Group 1 (exit 1, no output)'
else
  bad "an unreferenced file did not come back clean (exit $rc, output: ${out:-<empty>}) — every finding would be downgraded and the command would report nothing actionable"
fi

out="$(bash "$SCRIPTS/verify-string-reference.sh" "$proj/src/orphan.ts" "$proj" 2>&1)"
rc=$?
if [ "$rc" -eq 1 ] && [ -z "$out" ]; then
  ok "the candidate's own lines are excluded when it is passed as an absolute path"
else
  bad "an absolute-path candidate matched itself (exit $rc, output: ${out:-<empty>})"
fi

# A generic stem must be searched by full basename only, or it matches
# unrelated prose everywhere and downgrades every finding into uselessness.
mkdir -p "$proj/src/widget"
echo 'export default 1;' > "$proj/src/widget/index.ts"
echo 'This paragraph mentions an index of terms.' > "$proj/NOTES.md"
out="$(bash "$SCRIPTS/verify-string-reference.sh" "src/widget/index.ts" "$proj" 2>&1)"
rc=$?
if [ "$rc" -eq 1 ]; then
  ok 'a generic stem (index.ts) does not match unrelated prose containing "index"'
else
  bad "generic stem over-matched (exit $rc, output: ${out:-<empty>})"
fi

echo

# --- record-rejection.sh -----------------------------------------------------

echo "-- record-rejection.sh --"

kproj="$TMP/kproj"
mkdir -p "$kproj"
printf '{\n  // keep: loaded by the CLI at runtime\n  "ignore": ["src/legacy.ts"]\n}\n' > "$kproj/knip.json"

out="$(bash "$SCRIPTS/record-rejection.sh" files "src/dynamic.ts" "reason" "$kproj" 2>&1)"
rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q 'unknown category'; then
  ok 'an unknown category is rejected with a named error, not a silent write'
else
  bad "unknown category was not rejected cleanly (exit $rc, output: $out)"
fi

bash "$SCRIPTS/record-rejection.sh" file "src/dynamic.ts" "loaded by name at runtime" "$kproj" >/dev/null 2>&1
target="$kproj/knip.jsonc"
[ -f "$target" ] || target="$kproj/knip.json"
if grep -q 'src/dynamic.ts' "$target" && grep -q 'loaded by name at runtime' "$target"; then
  ok 'a rejection is recorded together with its stated reason'
else
  bad "the rejection or its reason is missing from $(basename "$target")"
fi

if grep -q 'keep: loaded by the CLI at runtime' "$target"; then
  ok "a comment already in the user's config survives the edit"
else
  bad "an existing comment was dropped — the whole point of the text-surgery approach"
fi

out="$(bash "$SCRIPTS/record-rejection.sh" file "src/dynamic.ts" "second attempt" "$kproj" 2>&1)"
rc=$?
count="$(grep -c 'src/dynamic.ts' "$target")"
if [ "$rc" -eq 0 ] && [ "$count" -eq 1 ]; then
  ok 'recording the same finding twice is a no-op, not a duplicate entry'
else
  bad "duplicate handling is wrong (exit $rc, occurrences: $count)"
fi

# Whatever shape it writes, the result has to survive a JSONC read: strip
# comments and trailing commas, then it must be valid JSON.
if command -v python3 >/dev/null 2>&1; then
  if python3 - "$target" <<'PY' 2>/dev/null
import json, re, sys
raw = open(sys.argv[1]).read()
raw = re.sub(r'//[^\n]*', '', raw)
raw = re.sub(r',(\s*[}\]])', r'\1', raw)
json.loads(raw)
PY
  then
    ok 'the written config still parses as JSONC (comments + trailing commas stripped)'
  else
    bad 'the written config no longer parses — knip would fail to read its own config'
  fi
fi

echo

# --- run-knip.sh -------------------------------------------------------------

echo "-- run-knip.sh --"

out="$(bash "$SCRIPTS/run-knip.sh" "$TMP/definitely-not-a-directory" 2>&1)"
rc=$?
if [ "$rc" -eq 1 ] && printf '%s' "$out" | grep -qi 'knip unavailable'; then
  ok 'an unusable project directory exits 1 with a plain message, not a shell trace'
else
  bad "bad project dir was not handled cleanly (exit $rc, output: $out)"
fi

echo

# --- Summary -----------------------------------------------------------------

echo "== Summary =="
printf '  %d passed, %d failed\n' "$pass_count" "$fail_count"

if [ "$fail_count" -gt 0 ]; then
  echo "DEAD-CODE SCRIPTS TEST FAILED"
  exit 1
fi

echo "DEAD-CODE SCRIPTS TEST PASSED"
exit 0
