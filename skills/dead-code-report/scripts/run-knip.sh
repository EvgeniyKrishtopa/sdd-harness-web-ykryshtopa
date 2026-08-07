#!/usr/bin/env bash
# Runs knip via npx -- this plugin's rules forbid installing packages into a
# target project, so knip is always fetched on demand rather than added as a
# devDependency (harness-audit/v0.4.0-implemented/01-review-blind-spots.txt,
# point 2, step 1).
#
# Prints the JSON report (--reporter json, per knip's own docs) to stdout on
# success. On any failure to obtain a report -- npx missing, no network and
# nothing cached, knip erroring before it can analyze anything -- prints one
# clear message to stderr and exits 1. This must never look like a crash:
# "knip isn't available" is an expected, handled outcome, not a bug.
#
# Usage: run-knip.sh [project-dir]
set -u

PROJECT_DIR="${1:-.}"

if ! command -v npx >/dev/null 2>&1; then
  echo "knip unavailable: npx not found on PATH -- Node.js/npm is required to run knip." >&2
  exit 1
fi

cd "$PROJECT_DIR" 2>/dev/null || {
  echo "knip unavailable: cannot cd into project dir '$PROJECT_DIR'." >&2
  exit 1
}

stderr_file="$(mktemp)"
trap 'rm -f "$stderr_file"' EXIT

report="$(npx --yes knip --reporter json 2>"$stderr_file")"

# knip exits non-zero whenever it finds ANY issue at all -- that is the
# normal, successful case for this command, not a failure. Exit status alone
# can't tell "ran fine, found things" apart from "never ran", so the only
# reliable success signal is a report that actually looks like knip's JSON
# shape (a top-level "issues" array).
if printf '%s' "$report" | grep -q '"issues"'; then
  printf '%s\n' "$report"
  exit 0
fi

{
  echo "knip unavailable or failed to produce a report."
  echo "-- npx/knip stderr --"
  cat "$stderr_file"
  echo "----"
  echo "If this is the first time knip has run here, npx needs network access"
  echo "to fetch it once; if that's not available, install knip locally as a"
  echo "devDependency yourself (this command will not do it for you) and"
  echo "re-run."
} >&2
exit 1
