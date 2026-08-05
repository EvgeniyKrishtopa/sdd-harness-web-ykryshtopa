#!/usr/bin/env bash
# Heuristic grep for single-line `//` comments whose content looks like
# disabled code rather than prose (ends in `;`, `{`, `}`, `=>`, or opens with
# a keyword/JSX no one writes as a sentence). Not a parser, and it does not
# catch multi-line `/* */` blocks -- a cheap aid for step 1, not a source of
# truth. Every hit this script produces always lands in Group 2 ("needs a
# look") when classifying: a comment can never be verified "definitely dead"
# the way an unreferenced file can, so this script does not attempt to rank
# its own output.
#
# Usage: find-commented-code.sh [project-dir]
set -u

PROJECT_DIR="${1:-.}"
cd "$PROJECT_DIR" 2>/dev/null || {
  echo "cannot cd into '$PROJECT_DIR'" >&2
  exit 1
}

PATTERN='^[[:space:]]*//.*(;|\{|\}|=>)[[:space:]]*$|^[[:space:]]*//[[:space:]]*(const|let|var|function|return|import |export |if[[:space:]]*\(|for[[:space:]]*\(|class[[:space:]]|await |throw )'

matches_found=0
while IFS= read -r -d '' f; do
  hits="$(grep -nE "$PATTERN" "$f" 2>/dev/null)"
  if [ -n "$hits" ]; then
    matches_found=1
    printf '%s\n' "$hits" | sed "s|^|$f:|"
  fi
done < <(find . \
  \( -name node_modules -o -name .git -o -name dist -o -name build \
     -o -name coverage -o -name .next -o -name .turbo -o -name out \) -prune -o \
  -type f \( -name '*.js' -o -name '*.jsx' -o -name '*.ts' -o -name '*.tsx' \
             -o -name '*.mjs' -o -name '*.cjs' \) -print0)

if [ "$matches_found" -eq 0 ]; then
  echo "no commented-out code found by this heuristic."
fi
