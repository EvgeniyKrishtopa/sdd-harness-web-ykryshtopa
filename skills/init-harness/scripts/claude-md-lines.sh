#!/usr/bin/env bash
# Counts a project's root instruction file against the line budget in
# references/claude-md-budget.md, and the effective total once its
# @-imports are loaded too. An @-import is loaded into context in full, so
# it is not progressive disclosure: the effective total is what a session
# actually pays for.
#
# Usage: claude-md-lines.sh [file]
#   file defaults to CLAUDE.md, or AGENTS.md when there is no CLAUDE.md.
# Read-only. Exit 0 with the report, 2 when there is no file to count.

set -f
BUDGET=100
MAX_DEPTH=5 # Claude Code follows @-imports at most five hops deep

root="${1:-}"
if [ -z "$root" ]; then
  if [ -f CLAUDE.md ]; then root=CLAUDE.md
  elif [ -f AGENTS.md ]; then root=AGENTS.md
  else echo "no CLAUDE.md or AGENTS.md in $(pwd)"; exit 2
  fi
fi
[ -f "$root" ] || { echo "no such file: $root"; exit 2; }

# awk, not wc -l: a last line without a newline still counts.
count_lines() { awk 'END { print NR }' "$1"; }

canonical() { printf '%s/%s' "$(cd "$(dirname "$1")" && pwd -P)" "$(basename "$1")"; }

# @-references outside fenced code blocks and inline code spans, the same
# places Claude Code skips. Trailing punctuation is prose, not path.
imports_of() {
  awk '/^[[:space:]]*(```|~~~)/ { fenced = !fenced; next }
       !fenced { gsub(/`[^`]*`/, ""); print }' "$1" |
    grep -oE '(^|[[:space:](])@[^[:space:]]+' |
    sed -E 's/^[[:space:](]*@//; s/[.,;:)]+$//'
}

seen="|$(canonical "$root")|"
total=0
imports=0

visit() {
  local file="$1" depth="$2" dir ref target key n
  [ "$depth" -lt "$MAX_DEPTH" ] || return 0
  dir="$(dirname "$file")"
  for ref in $(imports_of "$file"); do
    case "$ref" in
      "~/"*) target="$HOME/${ref#\~/}" ;;
      /*) target="$ref" ;;
      *) target="$dir/$ref" ;;
    esac
    [ -f "$target" ] || continue # @types/node and the like: not a file
    key="$(canonical "$target")"
    case "$seen" in *"|$key|"*) continue ;; esac
    seen="$seen$key|"
    n="$(count_lines "$target")"
    total=$((total + n))
    imports=$((imports + 1))
    printf 'import %s %s lines\n' "${target#./}" "$n"
    visit "$target" $((depth + 1))
  done
}

root_lines="$(count_lines "$root")"
if [ "$root_lines" -gt "$BUDGET" ]; then
  verdict="over by $((root_lines - BUDGET))"
else
  verdict="within"
fi
printf 'root %s %s lines, budget %s: %s\n' "$root" "$root_lines" "$BUDGET" "$verdict"
visit "$root" 0
total=$((total + root_lines))
printf 'effective %s lines (root + %s imports)\n' "$total" "$imports"
