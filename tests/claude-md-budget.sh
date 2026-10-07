#!/usr/bin/env bash
# Behaviour test for skills/init-harness/scripts/claude-md-lines.sh, the
# counter Gate 6 and init-harness use for the root instruction file's line
# budget (skills/init-harness/references/claude-md-budget.md).
#
# The size finding is CONFIRMED because it is a count, not a judgement, so
# the count has to be right: over/within at the edge, @-imports followed but
# never the ones in code, missing paths ignored, each file counted once.
# Also checks that the budget is stated the same in the doc and the script,
# and that no older budget number survives anywhere in the plugin.
#
# Run from anywhere:
#   bash tests/claude-md-budget.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/init-harness/scripts/claude-md-lines.sh"
DOC="$ROOT/skills/init-harness/references/claude-md-budget.md"

pass_count=0
fail_count=0

ok()  { printf '  [OK]   %s\n' "$1"; pass_count=$((pass_count + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail_count=$((fail_count + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

lines_file() { # path count
  mkdir -p "$(dirname "$1")"
  : > "$1"
  i=1
  while [ "$i" -le "$2" ]; do echo "line $i" >> "$1"; i=$((i + 1)); done
}

new_repo() { REPO="$TMP/$1"; mkdir -p "$REPO"; }

run() { (cd "$REPO" && bash "$SCRIPT" "$@"); }

expect() { # label expected-line [args...]
  local label="$1" want="$2"; shift 2
  local out; out="$(run "$@")"
  if printf '%s\n' "$out" | grep -qxF "$want"; then
    ok "$label"
  else
    bad "$label: wanted \"$want\", got:"; printf '%s\n' "$out" | sed 's/^/         /'
  fi
}

expect_absent() { # label unwanted-substring
  local out; out="$(run)"
  if printf '%s\n' "$out" | grep -qF "$2"; then bad "$1: found \"$2\""; else ok "$1"; fi
}

echo "== CLAUDE.md line budget :: behaviour test =="
echo

echo "-- one budget, stated once --"

script_budget="$(sed -n 's/^BUDGET=\([0-9][0-9]*\).*/\1/p' "$SCRIPT")"
if grep -q "^## The budget: ${script_budget} lines" "$DOC"; then
  ok "script BUDGET ($script_budget) matches the doc's heading"
else
  bad "script BUDGET ($script_budget) and $DOC disagree"
fi

stale="$(grep -rnE '(roughly|near|under) 200 lines' "$ROOT/skills" "$ROOT/agents" 2>/dev/null)"
if [ -z "$stale" ]; then
  ok "no older 200-line budget left in skills/ or agents/"
else
  bad "older budget still stated:"; printf '%s\n' "$stale" | sed 's/^/         /'
fi

echo
echo "-- root count against the budget --"

new_repo over
lines_file "$REPO/CLAUDE.md" 130
expect "130 lines is over" "root CLAUDE.md 130 lines, budget 100: over by 30"

new_repo within
lines_file "$REPO/CLAUDE.md" 90
expect "90 lines is within" "root CLAUDE.md 90 lines, budget 100: within"

new_repo edge
lines_file "$REPO/CLAUDE.md" 100
expect "exactly 100 is within" "root CLAUDE.md 100 lines, budget 100: within"

new_repo no-newline
lines_file "$REPO/CLAUDE.md" 100
printf 'last line, no newline' >> "$REPO/CLAUDE.md"
expect "a last line without a newline still counts" "root CLAUDE.md 101 lines, budget 100: over by 1"

new_repo agents
lines_file "$REPO/AGENTS.md" 12
expect "falls back to AGENTS.md" "root AGENTS.md 12 lines, budget 100: within"

new_repo none
out="$(run)"; code=$?
if [ "$code" -eq 2 ]; then ok "no file → exit 2"; else bad "no file → exit $code, wanted 2 ($out)"; fi

echo
echo "-- effective count with @-imports --"

new_repo imports
lines_file "$REPO/.claude/docs/gates.md" 40
lines_file "$REPO/docs/nested.md" 5
echo "@../../docs/nested.md" >> "$REPO/.claude/docs/gates.md"   # 41 lines
lines_file "$REPO/CONTEXT.md" 7
cat > "$REPO/CLAUDE.md" <<'EOF'
# Project
- @.claude/docs/gates.md — gates.
- (@CONTEXT.md), glossary.
- @CONTEXT.md again: counted once.
- Bump `@types/node` with Node; mail me at dev@example.com.
- @docs/missing.md does not exist.
```
@docs/in-fence.md
```
EOF
lines_file "$REPO/docs/in-fence.md" 50
expect "root counted alone" "root CLAUDE.md 9 lines, budget 100: within"
expect "import counted" "import .claude/docs/gates.md 41 lines"
expect "nested import followed, relative to its importer" "import .claude/docs/../../docs/nested.md 5 lines"
expect "import in parentheses, counted once" "import CONTEXT.md 7 lines"
expect "effective = root + each file once" "effective 62 lines (root + 3 imports)"
expect_absent "fenced @-reference ignored" "in-fence.md"
expect_absent "missing file ignored" "missing.md"

new_repo cycle
printf '@b.md\n' > "$REPO/a.md"
printf '@a.md\n' > "$REPO/b.md"
printf '@a.md\n' > "$REPO/CLAUDE.md"
expect "import cycle terminates" "effective 3 lines (root + 2 imports)"

echo
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
