#!/usr/bin/env bash
# Step 3's safety net: before a finding is allowed into Group 1 ("reliable"),
# search the whole project for the candidate file's own name as plain text --
# including inside a string literal, a config value, a comment. If it turns
# up anywhere, static analysis already missed the reference that explains it,
# and the finding must be downgraded to Group 3, not deleted.
# See harness-audit/v0.4.0-planned/05-design-rationale.txt, decision 4.
#
# Only node_modules and .git are excluded: node_modules per the plan
# ("кроме node_modules"), and .git alongside it because it holds history, not
# the project as it stands today -- grepping packfiles is noise, not signal.
# Everything else, including built output, stays in scope: a hit there is
# itself evidence the file is actually consumed.
#
# Generic stems (index, utils, types, ...) are searched by their full
# basename only, not the bare stem -- the bare stem would match unrelated
# prose constantly and turn every finding into Group 3, which defeats the
# point. This is the one place this script narrows the search; it never
# widens past what step 3 asks for.
#
# Usage: verify-string-reference.sh <path-to-candidate-file> [project-dir]
# Exit 0 + prints matches  -> a string reference was found. DOWNGRADE this
#                              finding to Group 3.
# Exit 1, no output        -> nothing found. The finding may stay in Group 1.
set -u

CANDIDATE="${1:?usage: verify-string-reference.sh <path-to-candidate-file> [project-dir]}"
PROJECT_DIR="${2:-.}"

cd "$PROJECT_DIR" 2>/dev/null || {
  echo "cannot cd into '$PROJECT_DIR'" >&2
  exit 2
}

basename_full="$(basename "$CANDIDATE")"
basename_stem="${basename_full%.*}"

GENERIC_STEMS='^(index|main|utils?|helpers?|types?|constants?|config|styles?|common|shared|base)$'

search_terms=(-e "$basename_full")
if ! printf '%s' "$basename_stem" | grep -qiE "$GENERIC_STEMS"; then
  search_terms+=(-e "$basename_stem")
fi

matches="$(grep -rn --binary-files=without-match \
  --exclude-dir=node_modules --exclude-dir=.git \
  "${search_terms[@]}" . 2>/dev/null | grep -vF "$CANDIDATE")"

if [ -n "$matches" ]; then
  printf '%s\n' "$matches"
  exit 0
fi
exit 1
