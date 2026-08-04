#!/usr/bin/env bash
# Behavioural test for hooks/hooks.json.
#
# The smoke test checks that the hook file has the right *shape*. This one
# checks that the hooks *do the right thing*: it builds a throwaway git repo
# from the vite-vitest-yarn fixture, extracts each hook's command straight
# out of hooks.json, feeds it the same stdin Claude Code would, and asserts
# on the decision it returns.
#
# It needs git, jq and a POSIX shell. Nothing is installed and nothing
# outside the temporary directory is touched — no network, no dependencies.
#
#   bash tests/hook-behaviour.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
HOOKS="$ROOT/hooks/hooks.json"

if ! command -v jq >/dev/null 2>&1; then
  echo "jq is required for this test (the hook commands live inside JSON)." >&2
  exit 2
fi

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
CMD="$WORK/cmds"; REPO="$WORK/repo"
mkdir -p "$CMD" "$REPO"

jq -r '.hooks.PreToolUse[0].hooks[0].command'   "$HOOKS" > "$CMD/commit.sh"
jq -r '.hooks.PreToolUse[0].hooks[1].command'   "$HOOKS" > "$CMD/merge.sh"
jq -r '.hooks.PreToolUse[0].hooks[2].command'   "$HOOKS" > "$CMD/push.sh"
jq -r '.hooks.PreToolUse[1].hooks[0].command'   "$HOOKS" > "$CMD/ignore.sh"
jq -r '.hooks.Stop[0].hooks[0].command'         "$HOOKS" > "$CMD/stop.sh"
jq -r '.hooks.SessionStart[0].hooks[0].command' "$HOOKS" > "$CMD/session.sh"

cp -R "$ROOT/tests/fixtures/vite-vitest-yarn/." "$REPO/"
cd "$REPO" || exit 1
git init -q -b main
git add -A
git -c user.email=t@example.com -c user.name=test commit -qm "init fixture"
# what init-harness would have written into the target repo
mkdir -p .claude
printf 'node_modules\ndist\ncoverage\n.git\n*.log\nyarn.lock\n' > .claudeignore

pass=0; fail=0
verdict() { # verdict <name> <expected-substring> <actual>
  if printf '%s' "$3" | grep -q "$2"; then
    printf '  [PASS] %s\n' "$1"; pass=$((pass + 1))
  else
    printf '  [FAIL] %s\n         got: %s\n' "$1" "$(printf '%s' "$3" | head -c 300)"
    fail=$((fail + 1))
  fi
}
verdict_absent() { # verdict_absent <name> <unwanted-substring> <actual>
  if printf '%s' "$3" | grep -q "$2"; then
    printf '  [FAIL] %s\n         got: %s\n' "$1" "$(printf '%s' "$3" | head -c 300)"
    fail=$((fail + 1))
  else
    printf '  [PASS] %s\n' "$1"; pass=$((pass + 1))
  fi
}
bash_in() { printf '{"tool_name":"Bash","tool_input":{"command":"%s"}}' "$1"; }

echo "== sdd-harness-web-ykryshtopa :: hook behaviour =="
echo "Throwaway repo: $REPO"
echo

echo "-- SessionStart --"
verdict "prints branch, status and recent commits" "=== Recent commits ===" \
  "$(sh "$CMD/session.sh" </dev/null 2>&1)"

# #U3: SessionStart also surfaces PROGRESS.md's Status/Next steps, but only
# when the file exists — a repo that hasn't adopted it yet must see nothing
# extra, not an empty "=== Progress ===" header.
rm -f PROGRESS.md
out="$(CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/session.sh" </dev/null 2>&1; echo "EXIT=$?")"
verdict "no PROGRESS.md -> exits 0" "EXIT=0" "$out"
verdict_absent "no PROGRESS.md -> prints no Progress section" "=== Progress" "$out"

cat > PROGRESS.md <<'EOF'
# Progress

## Current change
- Change: demo-change
- Branch: feature/demo
- Last commit: abc123 -- demo commit

## Status
- Done: 1
- In progress: none
- Blocked: none

## Next steps
1. Do the first documented thing
2. Do the second documented thing

## Session log
- Clock-in: 2026-08-01T00:00:00Z -- Clock-out: 2026-08-01T01:00:00Z
EOF
out="$(CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/session.sh" </dev/null 2>&1; echo "EXIT=$?")"
verdict "with PROGRESS.md -> prints Progress section" "=== Progress" "$out"
verdict "with PROGRESS.md -> prints next steps" "Do the first documented thing" "$out"
verdict "with PROGRESS.md -> exits 0" "EXIT=0" "$out"

# Malformed structure (no recognizable "## Status"/"## Next steps" headings,
# a stray "##" inside a body line): must not crash the hook, just print
# nothing extra.
cat > PROGRESS.md <<'EOF'
Just some free text someone dropped in this file by hand.
### An unrelated heading level
A line that mentions ## Status without being one.
EOF
out="$(CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/session.sh" </dev/null 2>&1; echo "EXIT=$?")"
verdict "malformed PROGRESS.md -> exits 0, does not crash" "EXIT=0" "$out"
rm -f PROGRESS.md
echo

echo "-- PreToolUse: git commit guard --"
git checkout -q main
verdict "on the default branch -> ask" '"permissionDecision":"ask"' \
  "$(bash_in "git commit -m x" | sh "$CMD/commit.sh")"

git checkout -q -b feature/test
echo "// harmless" >> src/utils/sum.ts && git add -A
verdict "feature branch, ordinary diff -> allow" '"permissionDecision":"allow"' \
  "$(bash_in "git commit -m x" | sh "$CMD/commit.sh")"

printf 'const api_key = "AKIAIOSFODNN7EXAMPLE";\n' > src/secret.ts && git add -A
verdict "staged secret-shaped string -> ask" 'secret-like pattern' \
  "$(bash_in "git commit -m x" | sh "$CMD/commit.sh")"
git rm -q --cached src/secret.ts >/dev/null; rm -f src/secret.ts

printf 'export const env = process.env.API_KEY;\n' > src/envuse.ts && git add -A
verdict "process.env reference is not a false positive -> allow" '"permissionDecision":"allow"' \
  "$(bash_in "git commit -m x" | sh "$CMD/commit.sh")"
git rm -q --cached src/envuse.ts >/dev/null; rm -f src/envuse.ts

awk 'BEGIN { for (i = 0; i < 600; i++) printf "export const v%d = %d;\n", i, i }' > src/big.ts
git add -A
verdict "600-line diff -> ask (large commit)" 'Large commit' \
  "$(bash_in "git commit -m x" | sh "$CMD/commit.sh")"
git rm -q --cached src/big.ts >/dev/null; rm -f src/big.ts; git add -A

git stash -q -u 2>/dev/null
git checkout -q --detach
verdict "detached HEAD -> ask" 'Detached HEAD' \
  "$(bash_in "git commit -m x" | sh "$CMD/commit.sh")"
git checkout -q feature/test; git stash pop -q 2>/dev/null
echo

echo "-- PreToolUse: git merge / git push guards --"
git checkout -q main
verdict "merge into the default branch -> ask" '"permissionDecision":"ask"' \
  "$(bash_in "git merge feature/test" | sh "$CMD/merge.sh")"
git checkout -q feature/test
verdict "merge on a feature branch -> allow" '"permissionDecision":"allow"' \
  "$(bash_in "git merge origin/x" | sh "$CMD/merge.sh")"
verdict "force push -> ask" 'Force-push' \
  "$(bash_in "git push --force origin feature/test" | sh "$CMD/push.sh")"
verdict "ordinary push from a feature branch -> allow" '"permissionDecision":"allow"' \
  "$(bash_in "git push -u origin feature/test" | sh "$CMD/push.sh")"
verdict "push naming the protected branch -> ask" 'protected branch by name' \
  "$(bash_in "git push origin main" | sh "$CMD/push.sh")"
echo

echo "-- PreToolUse: .claudeignore guard --"
mkdir -p coverage && echo "<html>" > coverage/index.html
verdict "covered path -> deny" '"permissionDecision":"deny"' \
  "$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/coverage/index.html"}}' "$REPO" \
     | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/ignore.sh")"
verdict "ordinary source file -> allow" '"permissionDecision":"allow"' \
  "$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/src/App.tsx"}}' "$REPO" \
     | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/ignore.sh")"
verdict "covered path while cwd is a subdirectory -> still deny" '"permissionDecision":"deny"' \
  "$(cd src && printf '{"tool_name":"Grep","tool_input":{"path":"%s/coverage"}}' "$REPO" \
     | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/ignore.sh")"
echo

echo "-- Stop: typecheck guard --"
printf 'echo "MARKER-FROM-MANIFEST" >&2; exit 1\n' > tc.sh
mkdir -p .claude   # `git stash -u` above prunes it: it is empty and untracked
cat > .claude/harness.json <<'JSON'
{ "version": 1, "runCmd": "sh", "scripts": { "typecheck": "tc.sh" } }
JSON
out="$(echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/stop.sh" 2>&1; echo "EXIT=$?")"
verdict "failing typecheck -> exit 2" "EXIT=2" "$out"
verdict "the command came from .claude/harness.json" "MARKER-FROM-MANIFEST" "$out"
out="$(echo '{"stop_hook_active":true}' | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/stop.sh" 2>&1; echo "EXIT=$?")"
verdict "stop_hook_active -> exit 0" "EXIT=0" "$out"
verdict "stop_hook_active -> typecheck not run at all" "^EXIT=0$" "$out"
printf 'exit 0\n' > tc.sh
out="$(echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/stop.sh" 2>&1; echo "EXIT=$?")"
verdict "passing typecheck -> exit 0" "EXIT=0" "$out"
rm -f .claude/harness.json
out="$(echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/stop.sh" 2>&1; echo "EXIT=$?")"
verdict "no manifest and no local tsc -> skip, never reach for npx" "EXIT=0" "$out"
verdict "no manifest -> says why it skipped" "no typecheck command" "$out"
mv tsconfig.json tsconfig.json.off
out="$(echo '{"stop_hook_active":false}' | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/stop.sh" 2>&1; echo "EXIT=$?")"
verdict "no tsconfig.json -> exit 0" "EXIT=0" "$out"
mv tsconfig.json.off tsconfig.json
echo

echo "== Summary =="
printf '  %d passed, %d failed\n' "$pass" "$fail"
if [ "$fail" -gt 0 ]; then
  echo "HOOK BEHAVIOUR TEST FAILED"
  exit 1
fi
echo "HOOK BEHAVIOUR TEST PASSED"
exit 0
