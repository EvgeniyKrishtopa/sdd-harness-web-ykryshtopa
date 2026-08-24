#!/usr/bin/env bash
# Builds the throwaway repository a regression case is measured against:
# a clean minimal project, committed, plus exactly one named defect left
# uncommitted on top of it.
#
# Usage:  EVAL_DEFECT=<name> bash make-repo.sh [target-dir]
#
# The case picks the defect through EVAL_DEFECT in its prompt.md frontmatter.
# An unknown or empty name is a hard error: a case that quietly received a
# clean repository would pass forever while measuring nothing.
#
# Registered defects:
#   harness-config-drift — CLAUDE.md claims six review gates while
#                          .claude/docs/review-gates.md lists seven.
#
# Adding a case means adding a named block at the bottom of this file, so
# every planted defect stays readable in one place.

set -euo pipefail

target="${1:-$PWD}"
defect="${EVAL_DEFECT:-}"

die() { printf 'make-repo.sh: %s\n' "$1" >&2; exit 1; }

[ -n "$defect" ] || die "EVAL_DEFECT is not set — refusing to build a repository with no defect in it"
[ -d "$target" ] || die "target directory does not exist: $target"
if [ -e "$target/.git" ]; then die "refusing to run in an existing repository: $target"; fi

# Never build on top of a real checkout: the sandbox is a fresh empty
# directory, and anything else is somebody's working tree.
probe="$(cd "$target" && pwd)"
while [ "$probe" != "/" ]; do
  if [ -e "$probe/.claude-plugin/plugin.json" ]; then die "refusing to run inside a plugin checkout: $probe"; fi
  probe="$(dirname "$probe")"
done

cd "$target"

# ---------------------------------------------------------------- clean state

mkdir -p .claude/docs src

support_manifest="$(dirname "$0")/harness.json"
if [ -f "$support_manifest" ]; then
  cp "$support_manifest" .claude/harness.json
else
  cat > .claude/harness.json <<'JSON'
{
  "version": 1,
  "harnessVersion": "0.8.0",
  "forge": "other",
  "framework": "vite",
  "packageManager": "npm",
  "runCmd": "npm run",
  "testRunner": "vitest",
  "buildDir": "dist",
  "lockfile": "package-lock.json",
  "coverageThreshold": 80,
  "scripts": { "dev": "dev", "typecheck": "typecheck", "lint": "lint", "testCoverage": "test:coverage" },
  "devServerUrl": "http://localhost:5173",
  "trivialDiffThreshold": 10,
  "trivialDiffPaths": ["*.md", "*.css", "*.svg", "public/**"],
  "maxFixAttempts": 2,
  "disabledRules": [],
  "models": {}
}
JSON
fi

cat > package.json <<'JSON'
{
  "name": "eval-sandbox",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "vite",
    "typecheck": "tsc --noEmit",
    "lint": "eslint .",
    "test:coverage": "vitest run --coverage"
  }
}
JSON

cat > .claude/docs/review-gates.md <<'DOC'
# Automated Review Gates

- **Gate 1 — architecture-review**, after `design.md` is drafted.
- **Gate 2 — spec-review**, after the full artifact set is done.
- **Gate 2b — scaffold-review**, inside `opsx-scaffold`, on a change whose
  proposal step judged it needs a scaffold.
- **Gate 3 — web-qa**, on the last group only, if the change touched
  user-facing UI.
- **Gate 4 + Gate 5 — code-review**, once per run: correctness/
  simplification and test-coverage gaps in one delegation.
- **Gate 6 — harness-review**, on the run's last group with pending tasks,
  when the run touched something it could review.
DOC

cat > CLAUDE.md <<'DOC'
# Project instructions

<!-- sdd-harness-web-ykryshtopa: pointer block -->

This repository is set up with the spec-driven OpenSpec harness. Its seven
automated review gates are described in `.claude/docs/review-gates.md`, and
the git workflow in `.claude/docs/git-conventions.md`.

Run configuration lives in `.claude/harness.json` — it is the single source
of truth every skill and hook reads.
DOC

cat > src/upload.ts <<'TS'
export async function uploadAvatar(file: File): Promise<string> {
  const body = new FormData();
  body.append("file", file);
  const response = await fetch("/api/avatar", { method: "POST", body });
  if (!response.ok) throw new Error(`upload failed: ${response.status}`);
  const { url } = await response.json();
  return url;
}
TS

git init -q .
git config user.email "eval@example.invalid"
git config user.name "Eval Sandbox"
git add -A
git commit -q -m "chore: minimal project with the harness configured"

# -------------------------------------------------------------- the defect

case "$defect" in
  harness-config-drift)
    # 0.7.0 shipped a seventh gate; six places still claimed six. Here the
    # pointer block is the stale copy and review-gates.md is the truth, left
    # uncommitted so the run under review is the one that introduced it.
    perl -0pi -e 's/Its seven\n/Its six\n/' CLAUDE.md
    grep -q "Its six" CLAUDE.md || die "defect $defect did not apply"
    ;;
  *)
    die "unknown EVAL_DEFECT: $defect"
    ;;
esac

printf 'make-repo.sh: built %s with defect %s\n' "$target" "$defect" >&2
