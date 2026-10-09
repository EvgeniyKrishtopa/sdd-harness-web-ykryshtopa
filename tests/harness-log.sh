#!/usr/bin/env bash
# harness-log.sh -- the per-branch harness log (0.12.0): the path every
# writer appends to, and the one read every reader uses, run for real in
# bash and in zsh. The snippets are taken from the reference text itself, so
# a change to the documented form is what gets tested.
#
# Usage: bash tests/harness-log.sh   (from the plugin root)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
REF="$ROOT/skills/opsx-apply-git/references/log-findings.md"
pass=0; fail=0
ok()  { printf '  [PASS] %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail=$((fail + 1)); }
check() { if [ "$3" = "$2" ]; then ok "$1"; else bad "$1 (expected '$2', got '$3')"; fi; }

command -v jq >/dev/null 2>&1 || { echo "jq is required"; exit 1; }

write_line=$(grep -m1 '^printf .*>> ".claude/harness-log/' "$REF")
read_line=$(awk '/^\*\*Reading the log\*\*/{f=1} f && /^\{ awk 1 /{print; exit}' "$REF")
[ -n "$write_line" ] || { echo "no writer line found in $REF"; exit 1; }
[ -n "$read_line" ] || { echo "no reader line found in $REF"; exit 1; }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

shells="bash"
command -v zsh >/dev/null 2>&1 && shells="bash zsh"

for sh in $shells; do
  echo "-- $sh --"
  repo="$WORK/$sh"; mkdir -p "$repo"
  git -C "$repo" init -q -b feature/add-login
  git -C "$repo" config user.email t@example.com; git -C "$repo" config user.name t
  git -C "$repo" commit -q --allow-empty -m base

  # Nothing logged yet: the read is empty and does not fail.
  out=$(cd "$repo" && "$sh" -c "$read_line" | wc -l | tr -d ' ')
  check "no log at all -> empty read" "0" "$out"

  # The writer, with "/" in the branch name.
  line='{"ts":"2026-03-01T00:00:00Z","change":"c","gate":"spec-review","verdict":"new"}'
  printf '%s' "$line" > "$repo/.line.json"
  writer=$(printf '%s' "$write_line" | sed 's|"<line>"|"$(cat .line.json)"|')
  (cd "$repo" && mkdir -p .claude/harness-log && "$sh" -c "$writer")
  check "a/b branch -> a--b.jsonl" "yes" "$([ -f "$repo/.claude/harness-log/feature--add-login.jsonl" ] && echo yes || echo no)"

  # An upgraded project's old file, without a final newline, plus a second branch file.
  printf '%s' '{"ts":"2026-01-01T00:00:00Z","change":"c","gate":"spec-review","verdict":"old"}' > "$repo/.claude/harness-log.jsonl"
  printf '%s\n' '{"ts":"2026-02-01T00:00:00Z","change":"c","gate":"spec-review","verdict":"mid"}' > "$repo/.claude/harness-log/main.jsonl"

  out=$(cd "$repo" && "$sh" -c "$read_line" | jq -R 'fromjson?' | jq -s length)
  check "old file + two branch files -> all 3 lines, none glued" "3" "$out"

  out=$(cd "$repo" && "$sh" -c "$read_line" | jq -R 'fromjson?' \
    | jq -sr '[.[] | select(.gate == "spec-review")] | sort_by(.ts) | last | .verdict')
  check "latest line is picked by ts, not by file order" "new" "$out"
done

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
