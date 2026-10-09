#!/usr/bin/env bash
# traceability.sh -- the requirement-ID coverage snippet in
# skills/code-review/references/traceability-prefilter.md, run as written
# (extracted from the doc, only the change slug filled in) against a small
# throwaway repo. 0.12.0: one marker may list several identifiers.
#
# Usage: bash tests/traceability.sh   (from the plugin root)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/skills/code-review/references/traceability-prefilter.md"
pass=0; fail=0
ok()  { printf '  [PASS] %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail=$((fail + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
SNIPPET="$WORK/check.sh"
awk '/^```bash$/{f=1;next} /^```$/{if(f)exit} f' "$DOC" | sed 's/<change-slug>/x/' > "$SNIPPET"
grep -q 'change="x"' "$SNIPPET" || { echo "could not extract the snippet from $DOC"; exit 1; }

# run <proposal ids> <file content>: prints the snippet's one-line answer
run() {
  local repo="$WORK/repo"; rm -rf "$repo"; mkdir -p "$repo/openspec/changes/x" "$repo/src"
  printf '%s\n' "$1" > "$repo/openspec/changes/x/proposal.md"
  printf '%s\n' "$2" > "$repo/src/a.ts"
  (cd "$repo" && bash "$SNIPPET")
}
expect() { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1 (got: $2)"; fi; }

echo "-- one identifier per marker, as before --"
expect "single marker" "$(run 'FR-1' '// implements FR-1 of x')" "all requirement IDs covered"

echo "-- a list covers every identifier in it --"
expect "comma list" "$(run 'FR-4 NFR-3' '// implements FR-4, NFR-3 of x')" "all requirement IDs covered"
expect "and list" "$(run 'FR-4 NFR-3' '// implements FR-4 and NFR-3 of x')" "all requirement IDs covered"
expect "comma and list" "$(run 'FR-1 FR-2 NFR-3' '/* implements FR-1, FR-2, and NFR-3 of x */')" "all requirement IDs covered"
expect "middle of a list" "$(run 'FR-2' '// implements FR-1, FR-2, FR-3 of x')" "all requirement IDs covered"

echo "-- what a list must not cover --"
expect "an id missing from the list" "$(run 'FR-4 FR-5' '// implements FR-4, NFR-3 of x')" "uncovered requirement IDs: FR-5"
expect "FR-1 is not inside FR-10" "$(run 'FR-1' '// implements FR-10, FR-11 of x')" "uncovered requirement IDs: FR-1"
expect "another change's list" "$(run 'FR-1' '// implements FR-1, FR-2 of x-v2')" "uncovered requirement IDs: FR-1"
expect "no identifiers in the proposal" "$(run 'no ids here' '// implements FR-1 of x')" "traceability unavailable: no FR-/NFR- identifiers in openspec/changes/x/proposal.md"

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
