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

echo "-- the real SessionStart hook prints Status and Next steps --"
HOOK=$(jq -r '.. | .command? // empty' "$ROOT/hooks/hooks.json" | grep -F 'PROGRESS.md' | head -1)
HR="$WORK/hookrepo"; mkdir -p "$HR"; git -C "$HR" init -q
cp "$F" "$HR/PROGRESS.md"
out=$(cd "$HR" && bash -c "$HOOK" 2>/dev/null)
if printf '%s\n' "$out" | grep -qxF -- "- Blocked: none" \
   && printf '%s\n' "$out" | grep -qxF -- "1. Run group 3"; then
  ok "hook output has the Blocked line and step 1"
else
  bad "hook output missing Status/Next steps: $out"
fi

echo "-- the whole Next steps block, exactly --"
clock_out --next "A" --next "B" --next "C"
clock_out --next "A" --next "C"
block=$(awk '/^## Next steps$/{f=1;next} /^## /{f=0} f && NF' "$F" | tr '\n' '|')
if [ "$block" = "1. A|2. C|" ]; then ok "exactly 1. A, 2. C"; else bad "Next steps block: $block"; fi

echo "-- a slug that is a prefix of another --"
node "$P" pause --file "$F" --change add --date 2026-10-01 --reason "r1" >/dev/null
node "$P" pause --file "$F" --change add-search --date 2026-10-02 --reason "r2" >/dev/null
node "$P" pause --file "$F" --change add-zeta --date 2026-10-03 --reason "r3" >/dev/null
node "$P" clock-out --file "$F" --change add --branch b --last-commit "a — b" --done none \
  --in-progress none --blocked none --clock-in t1 --clock-out t2 >/dev/null
paused=$(awk '/^## Paused changes$/{f=1;next} /^## /{f=0} f && NF' "$F" | tr '\n' '|')
if [ "$paused" = "- add-search — paused 2026-10-02: r2|- add-zeta — paused 2026-10-03: r3|" ]; then
  ok "only 'add' removed; the others kept, in order"
else
  bad "Paused changes: $paused"
fi

echo "-- a title and a note before the first section are kept --"
printf '# Progress — my app\n\nRead me first.\n\n## Status\n\n- Done: none\n' > "$WORK/pre.md"
node "$P" clock-out --file "$WORK/pre.md" --change c --branch b --last-commit "a — b" --done 1 \
  --in-progress none --blocked none --clock-in t1 --clock-out t2 >/dev/null
if [ "$(head -3 "$WORK/pre.md")" = "$(printf '# Progress — my app\n\nRead me first.')" ]; then
  ok "preamble kept as written"
else
  bad "preamble changed: $(head -3 "$WORK/pre.md" | tr '\n' '|')"
fi

echo "-- a CRLF file: same call twice, same file, LF only --"
printf '# Progress\r\n\r\n## Session log\r\n\r\n- Clock-in: t1 — Clock-out: t2\r\n' > "$WORK/crlf.md"
crlf() { node "$P" clock-out --file "$WORK/crlf.md" --change c --branch b --last-commit "a — b" \
  --done 1 --in-progress none --blocked none --clock-in t1 --clock-out t2 >/dev/null; }
crlf; cp "$WORK/crlf.md" "$WORK/crlf1"; crlf
if cmp -s "$WORK/crlf.md" "$WORK/crlf1"; then ok "identical on the second call"; else bad "CRLF file changed on a repeated call"; fi
if [ "$(grep -c '^- Clock-in:' "$WORK/crlf.md")" = 1 ]; then ok "no duplicate session line"; else bad "duplicate session line"; fi
if grep -q "$(printf '\r')" "$WORK/crlf.md"; then bad "carriage returns left"; else ok "LF only"; fi

echo "-- a flag without its value is rejected --"
cp "$F" "$WORK/before-flag"
if node "$P" clock-out --file "$F" --change c --branch b --last-commit "a — b" --done 1 \
     --in-progress none --blocked --clock-in t1 --clock-out t2 2>/dev/null; then
  bad "--blocked without a value accepted"
else
  ok "exit non-zero"
fi
if cmp -s "$F" "$WORK/before-flag"; then ok "file untouched"; else bad "file changed"; fi
node "$P" clock-out --file "$F" --change c --branch b --last-commit "a — b" --done 1 \
  --in-progress none "--blocked=--no-verify was needed" --clock-in t1 --clock-out t2 >/dev/null
has "a value starting with -- via --name=value" "- Blocked: --no-verify was needed" "$F"

echo "-- a write that cannot happen fails cleanly --"
if node "$P" pause --file "$WORK/no-such-dir/PROGRESS.md" --change c --date d --reason r 2>"$WORK/err"; then
  bad "write into a missing directory succeeded"
else
  ok "exit non-zero"
fi
has "one-line message, no stack trace" "progress.mjs: cannot write" "$WORK/err"
if ls "$WORK"/no-such-dir 2>/dev/null | grep -q tmp; then bad "temporary file left behind"; else ok "no temporary file left"; fi

echo "-- a missing required value fails loudly and writes nothing --"
cp "$F" "$WORK/before"
if node "$P" clock-out --file "$F" --change x 2>/dev/null; then bad "missing values accepted"; else ok "exit non-zero"; fi
if cmp -s "$F" "$WORK/before"; then ok "file untouched"; else bad "file changed on a failed call"; fi

echo "-- pr-target: one line per parent, a new answer replaces it, clock-out keeps it --"
T="$WORK/target.md"
node "$P" pr-target --file "$T" --parent feature/a --target main --date 2026-10-09 >/dev/null
node "$P" pr-target --file "$T" --parent feature/ab --target feature/ab --date 2026-10-09 >/dev/null
cp "$T" "$WORK/target1"
node "$P" pr-target --file "$T" --parent feature/ab --target feature/ab --date 2026-10-09 >/dev/null
if cmp -s "$T" "$WORK/target1"; then ok "same answer twice, same file"; else bad "file changed on a repeated pr-target"; fi
node "$P" pr-target --file "$T" --parent feature/a --target feature/a --date 2026-10-10 >/dev/null
node "$P" clock-out --file "$T" --change c --branch b --last-commit "a — b" --done 1 \
  --in-progress none --blocked none --clock-in t1 --clock-out t2 >/dev/null
targets=$(awk '/^## PR target$/{f=1;next} /^## /{f=0} f && NF' "$T" | tr '\n' '|')
if [ "$targets" = "- feature/ab → feature/ab — chosen 2026-10-09|- feature/a → feature/a — chosen 2026-10-10|" ]; then
  ok "feature/a replaced, the prefix-sharing feature/ab kept, clock-out left both"
else
  bad "PR target: $targets"
fi
if node "$P" pr-target --file "$T" --parent feature/a --date 2026-10-10 2>/dev/null; then bad "missing --target accepted"; else ok "missing --target fails"; fi

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
