#!/usr/bin/env bash
# progress.sh -- skills/opsx-apply-git/scripts/progress.mjs, the only writer
# of PROGRESS.md's structured sections (0.12.0): same call twice gives the
# same file, numbering stays contiguous, sections it doesn't own survive,
# and the SessionStart hook still finds Status and Next steps.
#
# Usage: bash tests/progress.sh   (from the plugin root)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
P="$ROOT/skills/opsx-apply-git/scripts/progress.mjs"
pass=0; fail=0
ok()  { printf '  [PASS] %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail=$((fail + 1)); }
has()  { if grep -qF -- "$2" "$3"; then ok "$1"; else bad "$1 (no '$2' in $3)"; fi; }
hasnt() { if grep -qF -- "$2" "$3"; then bad "$1 ('$2' still in $3)"; else ok "$1"; fi; }

command -v node >/dev/null 2>&1 || { echo "node is required"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
F="$WORK/PROGRESS.md"

clock_out() {
  node "$P" clock-out --file "$F" --change add-login --branch feature/add-login \
    --last-commit "abc123 — feat: login form" --done "1, 2" --in-progress none \
    --blocked none --clock-in 2026-10-09T10:00:00Z --clock-out 2026-10-09T12:00:00Z "$@"
}

echo "-- clock-out on a missing file --"
clock_out --next "Run group 3" --next "Run group 4" --next "Run group 5"
has "creates the file with Current change" "- Change: add-login" "$F"
has "numbered steps" "3. Run group 5" "$F"
has "session line" "- Clock-in: 2026-10-09T10:00:00Z — Clock-out: 2026-10-09T12:00:00Z" "$F"

echo "-- the same clock-out twice changes nothing --"
cp "$F" "$WORK/first"
clock_out --next "Run group 3" --next "Run group 4" --next "Run group 5"
if cmp -s "$F" "$WORK/first"; then ok "identical file"; else bad "file changed on a repeated clock-out"; fi

echo "-- a step removed from the middle: numbering stays contiguous --"
clock_out --next "Run group 3" --next "Run group 5"
has "second step renumbered" "2. Run group 5" "$F"
hasnt "no third step left" "3. " "$F"

echo "-- no next steps --"
clock_out
has "says None." "None." "$F"

echo "-- pause, then clock-out of that change unpauses only it --"
node "$P" pause --file "$F" --change add-search --date 2026-10-01 --reason "waiting on design"
node "$P" pause --file "$F" --change add-billing --date 2026-10-02 --reason "blocked on legal"
node "$P" pause --file "$F" --change add-search --date 2026-10-03 --reason "again"
if [ "$(grep -c '^- add-search — ' "$F")" = 1 ]; then ok "pause is added once"; else bad "pause added twice"; fi
node "$P" clock-out --file "$F" --change add-search --branch feature/add-search \
  --last-commit "def456 — feat: search" --done none --in-progress 1 --blocked none \
  --clock-in 2026-10-09T13:00:00Z --clock-out 2026-10-09T14:00:00Z --next "Run group 2"
hasnt "resumed change leaves Paused changes" "- add-search — " "$F"
has "the other paused change stays" "- add-billing — paused 2026-10-02: blocked on legal" "$F"
node "$P" clock-out --file "$F" --change add-billing --branch feature/add-billing \
  --last-commit "0aa — x" --done none --in-progress none --blocked none \
  --clock-in 2026-10-09T15:00:00Z --clock-out 2026-10-09T16:00:00Z
hasnt "an empty Paused changes heading is dropped" "## Paused changes" "$F"
if [ "$(grep -c '^- Clock-in:' "$F")" = 3 ]; then ok "session log keeps every distinct session"; else bad "session log count wrong"; fi

echo "-- a value with a newline stays on one line --"
clock_out --blocked "$(printf 'group 3 —\nwaiting on API key')"
has "Blocked joined onto one line" "- Blocked: group 3 — waiting on API key" "$F"

echo "-- a section the script does not own survives --"
printf '\n## Notes\n\nKeep me.\n' >> "$F"
clock_out --next "Run group 3"
has "unknown section kept" "Keep me." "$F"

echo "-- the SessionStart hook still finds Status and Next steps --"
status=$(awk '/^## Status$/{f=1;next} /^## /{f=0} f' "$F" | grep -c '^- ')
steps=$(awk '/^## Next steps$/{f=1;next} /^## /{f=0} f' "$F" | grep -c '^1\. ')
if [ "$status" = 3 ] && [ "$steps" = 1 ]; then ok "headings and line shapes the hook reads"; else bad "hook extraction: status=$status steps=$steps"; fi

echo "-- a missing required value fails loudly and writes nothing --"
cp "$F" "$WORK/before"
if node "$P" clock-out --file "$F" --change x 2>/dev/null; then bad "missing values accepted"; else ok "exit non-zero"; fi
if cmp -s "$F" "$WORK/before"; then ok "file untouched"; else bad "file changed on a failed call"; fi

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
