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

# 0.12.0 review finding 3: a change-level check (spec-review here) runs on
# the parent branch, where nothing commits the log. Scenario a-f: spec-review
# writes on the parent, group 1 carries the file in its log commit, the plan
# is revised and spec-review writes again, group 2 carries that one, both
# PRs merge. With the per-run file both merge cleanly; with the branch's own
# file (the control) the second merge is an add/add conflict.
change_line=$(grep -m1 '^printf .*--<check>--' "$REF")
[ -n "$change_line" ] || { echo "no per-run writer line found in $REF"; exit 1; }
change_writer=$(printf '%s' "$change_line" | sed 's|"<line>"|"$(cat .line.json)"|; s|<check>|spec-review|')
branch_writer=$(printf '%s' "$write_line" | sed 's|"<line>"|"$(cat .line.json)"|')

# A date that returns $FAKE_UTC for the file-name format, so the two
# spec-review runs get two different seconds without waiting.
mkdir -p "$WORK/bin"
real_date=$(command -v date)
cat > "$WORK/bin/date" <<SHIM
#!/bin/sh
case "\$*" in *%Y%m%dT%H%M%SZ*) echo "\$FAKE_UTC" ;; *) exec "$real_date" "\$@" ;; esac
SHIM
chmod +x "$WORK/bin/date"

# scenario <name> <writer> -> prints "clean" or "conflict", leaves the repo in $WORK/<name>
scenario() {
  r="$WORK/$1"; w="$2"; mkdir -p "$r"
  git -C "$r" init -q -b main
  git -C "$r" config user.email t@example.com; git -C "$r" config user.name t
  git -C "$r" commit -q --allow-empty -m base
  git -C "$r" checkout -q -b feature/x
  log() { printf '%s' "{\"ts\":\"$2\",\"change\":\"x\",\"gate\":\"spec-review\",\"verdict\":\"$3\"}" > "$r/.line.json"
          (cd "$r" && mkdir -p .claude/harness-log && PATH="$WORK/bin:$PATH" FAKE_UTC="$1" bash -c "$w"); }
  commit_log() { git -C "$r" add .claude/harness-log/ && git -C "$r" commit -qm "chore: log this run's checks"; }
  # a) spec-review on the parent
  log 20261001T100000Z 2026-10-01T10:00:00Z first
  # b) group 1 carries it in its log commit
  git -C "$r" checkout -q -b feature/x-g1; echo 1 > "$r/g1.txt"; git -C "$r" add g1.txt; git -C "$r" commit -qm g1; commit_log
  # c) back on the parent the file is gone from the working tree
  git -C "$r" checkout -q feature/x
  # d) the plan is revised, spec-review writes again
  log 20261001T110000Z 2026-10-01T11:00:00Z second
  # e) group 2 carries its version
  git -C "$r" checkout -q -b feature/x-g2; echo 2 > "$r/g2.txt"; git -C "$r" add g2.txt; git -C "$r" commit -qm g2; commit_log
  # f) both PRs merge into the parent
  git -C "$r" checkout -q feature/x
  git -C "$r" merge -q --no-ff --no-edit feature/x-g1 >/dev/null 2>&1 || { echo conflict; return; }
  git -C "$r" merge -q --no-ff --no-edit feature/x-g2 >/dev/null 2>&1 || { echo conflict; return; }
  echo clean
}

echo "-- change-level check re-run between two groups --"
check "per-run file: both group PRs merge" "clean" "$(scenario per-run "$change_writer")"
out=$(cd "$WORK/per-run" && bash -c "$read_line" | jq -R 'fromjson?' | jq -s length)
check "per-run file: the read sees both spec-review lines" "2" "$out"
check "control, branch file: the second PR conflicts" "conflict" "$(scenario per-branch "$branch_writer")"

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
