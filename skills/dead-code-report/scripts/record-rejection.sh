#!/usr/bin/env bash
# Thin wrapper: the actual JSON/JSONC editing lives in record-rejection.mjs
# (bracket/string-aware text surgery, not a full re-serialize, so any
# comments already in the file are never dropped). See that file's header
# and harness-audit/v0.4.0-planned/05-design-rationale.txt, decision 3.
#
# Usage:
#   record-rejection.sh <category> <name> "<reason>" [project-dir]
#   category: file | dependency | binary | unresolved | export | type
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if ! command -v node >/dev/null 2>&1; then
  echo "record-rejection needs node on PATH -- the same requirement knip itself has via npx." >&2
  exit 2
fi

exec node "$SCRIPT_DIR/record-rejection.mjs" "$@"
