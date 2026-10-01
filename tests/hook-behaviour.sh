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
# The git guards call hooks/git-guard.sh through this variable, exactly as
# Claude Code sets it for an installed plugin.
export CLAUDE_PLUGIN_ROOT="$ROOT"

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
jq -r '.hooks.PreToolUse[0].hooks[3].command'   "$HOOKS" > "$CMD/ghapi.sh"
jq -r '.hooks.PreToolUse[1].hooks[0].command'   "$HOOKS" > "$CMD/ignore.sh"
jq -r '.hooks.Stop[0].hooks[0].command'         "$HOOKS" > "$CMD/stop.sh"
jq -r '.hooks.SessionStart[0].hooks[0].command' "$HOOKS" > "$CMD/session.sh"

cp -R "$ROOT/tests/fixtures/vite-vitest-yarn/." "$REPO/"
# The fixture is a runnable app, so anyone who starts it by hand (a live web-qa
# pass, say) leaves node_modules behind. It is gitignored, invisible in `git
# status`, and copying it in here silently changes what the hooks find: the
# Stop-hook case below asserts the "no manifest and no local tsc" path, and a
# real node_modules/.bin/tsc makes that path unreachable. The suite then fails
# on a machine where nothing about the plugin changed. Build artifacts are
# dropped for the same reason.
rm -rf "$REPO/node_modules" "$REPO/dist" "$REPO/coverage"
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
# bash_in breaks on newlines and quotes; multi-line and quoted commands go
# through jq instead.
bash_json() { jq -cn --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }
# lines <file> [n]: write an n-line (default 600) TypeScript file.
lines() { awk -v n="${2:-600}" 'BEGIN { for (i = 0; i < n; i++) printf "export const v%d = %d;\n", i, i }' > "$1"; }
# Throw away everything since the last commit, keeping what init-harness wrote.
# A mixed reset first, so files staged by a case are unstaged rather than deleted.
clean_tree() { git reset -q; git checkout -q -- .; git clean -qfd -e .claude -e .claudeignore; }

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

# The Claude Code version floor. The hook reads the running binary through
# CLAUDE_CODE_EXECPATH, so a stub that prints a version is enough to drive
# all three branches without installing anything.
stub() { printf 'echo "%s (Claude Code)"\n' "$1" > "$WORK/claude-stub"; chmod +x "$WORK/claude-stub"; }

stub "2.1.100"
out="$(CLAUDE_CODE_EXECPATH="$WORK/claude-stub" sh "$CMD/session.sh" </dev/null 2>&1; echo "EXIT=$?")"
verdict "below the floor -> warns, naming both versions" "Claude Code 2.1.100 is below the required 2.1.220" "$out"
verdict "below the floor -> still prints the git banner" "=== Branch ===" "$out"
verdict "below the floor -> exits 0 (a warning, not a block)" "EXIT=0" "$out"

# 2.1.9 vs 2.1.220 is the case a string comparison gets backwards.
stub "2.1.9"
verdict "2.1.9 is compared as a version, not a string" "2.1.9 is below the required" \
  "$(CLAUDE_CODE_EXECPATH="$WORK/claude-stub" sh "$CMD/session.sh" </dev/null 2>&1)"

stub "2.1.220"
verdict_absent "exactly at the floor -> no warning" "below the required" \
  "$(CLAUDE_CODE_EXECPATH="$WORK/claude-stub" sh "$CMD/session.sh" </dev/null 2>&1)"

stub "2.2.0"
verdict_absent "above the floor -> no warning" "below the required" \
  "$(CLAUDE_CODE_EXECPATH="$WORK/claude-stub" sh "$CMD/session.sh" </dev/null 2>&1)"

# Unreadable version: the banner is deliberately quieter than init-harness,
# which prints an explicit "skipped" line. Every session, in every repo, for
# what is usually a PATH quirk, would train people to ignore the banner.
out="$(CLAUDE_CODE_EXECPATH="$WORK/no-such-binary" sh "$CMD/session.sh" </dev/null 2>&1; echo "EXIT=$?")"
verdict_absent "unreadable version -> no warning" "below the required" "$out"
verdict "unreadable version -> exits 0, banner intact" "=== Branch ===" "$out"
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

echo "-- PreToolUse: guards read the command, not just the branch --"
# Claude Code's `if` filter is best-effort: a guard also runs when only one
# part of a compound command matches, and on any command with $(...), a
# heredoc, a loop or several lines. Each case below is a command that
# reached a guard in a real project and was wrongly asked about.
clean_tree
git checkout -q feature/test

c1='git checkout -b scratch && git show $(git log --format=%H main..HEAD | head -1)'
verdict_absent "incident 1: main..HEAD in a log range is not a push target" '"ask"' \
  "$(bash_json "$c1" | sh "$CMD/push.sh")"

c2=$(cat <<'CMD'
git add src && git commit -F - <<'EOF'
fix: tighten the parser

Remaining risk: none known.
EOF
CMD
)
verdict_absent "incident 2: 'Remaining' in a heredoc message is not a push" '"ask"' \
  "$(bash_json "$c2" | sh "$CMD/push.sh")"

c3=$(cat <<'CMD'
ids_file=$(mktemp)
for f in src/*.ts; do grep -l sum "$f" >> "$ids_file"; done
rm -f "$ids_file"
CMD
)
verdict_absent "incident 3: rm -f is not a force-push" '"ask"' \
  "$(bash_json "$c3" | sh "$CMD/push.sh")"

c4=$(cat <<'CMD'
git add -A && git commit -q -F - <<'EOF' && git push -q
chore: wire the parser

What remains: push to `main` after review.
EOF
gh pr create --base feature/base --title x --body "$(cat <<'BODY'
Merges into main once the remaining work lands.
BODY
)"
CMD
)
verdict "incident 4: push to own upstream, 'main' only in message bodies -> allow" \
  '"permissionDecision":"allow"' "$(bash_json "$c4" | sh "$CMD/push.sh")"

lines src/utils/sum.ts
c5='cd . && jq --arg v "$(date)" ".x = \$v" .claude/h.json > tmp && mv tmp .claude/h.json'
verdict_absent "incident 5: jq/mv with a dirty tree is not a commit" '"ask"' \
  "$(bash_json "$c5" | sh "$CMD/commit.sh")"
clean_tree

c9a='gh api repos/o/r/git/refs -f ref=refs/heads/x -f sha=abc'
c9b='gh api -X PATCH repos/o/r/git/refs/heads/x -f sha=abc'
verdict_absent "incident 9: gh api -f field is not a force-push (create ref)" '"ask"' \
  "$(bash_json "$c9a" | sh "$CMD/push.sh")"
verdict_absent "incident 9: gh api -f field is not a force-push (move ref)" '"ask"' \
  "$(bash_json "$c9b" | sh "$CMD/push.sh")"
c10='gh api repos/o/r/branches/main/protection'
verdict_absent "incident 10: main in an API path is not a push target" '"ask"' \
  "$(bash_json "$c10" | sh "$CMD/push.sh")"

git checkout -q main
c7='cd . && for p in react vite; do npm view $p version | head -20; done'
verdict_absent "incident 7: read-only loop on main is not a merge" '"ask"' \
  "$(bash_json "$c7" | sh "$CMD/merge.sh")"
c8=$(cat <<'CMD'
for f in a b; do printf '%s\n' "$(jq -nc --arg f "$f" '{f:$f}')" >> .claude/harness-log.jsonl; done
CMD
)
verdict_absent "incident 8: appending to a log on main is not a commit" '"ask"' \
  "$(bash_json "$c8" | sh "$CMD/commit.sh")"
echo

echo "-- PreToolUse: push guard, real pushes --"
verdict "push while on the protected branch -> ask" 'Pushing while on main' \
  "$(bash_json 'git push' | sh "$CMD/push.sh")"
git checkout -q --detach
verdict "push from detached HEAD -> ask" 'Detached HEAD' \
  "$(bash_json 'git push origin HEAD:feature/x' | sh "$CMD/push.sh")"
git checkout -q feature/test
for c in 'git push origin main' 'git push origin HEAD:main' \
         'git push origin HEAD:refs/heads/main' 'git push origin :main' \
         'npm test && git push origin main' 'git -C . push origin main' \
         'git push origin "main"'; do
  verdict "$c -> ask" 'protected branch by name' "$(bash_json "$c" | sh "$CMD/push.sh")"
done
for c in 'git push origin +main' 'git push -f origin feature/x' \
         'git push --force-with-lease=feature/x:abc origin feature/x' \
         'rm -f a && git push --force-with-lease' 'git push -uf origin feature/x'; do
  verdict "$c -> ask" 'Force-push' "$(bash_json "$c" | sh "$CMD/push.sh")"
done
for c in 'git push -u origin feature/x' 'git push origin feature/domain-fix' \
         'git push origin feature/maintenance' 'git push origin main-feature' \
         'git push origin chore/domain-main-x' \
         'git branch -f tmp HEAD && git push -u origin feature/x' \
         'git log origin/main..HEAD && git push -u origin feature/x'; do
  verdict "$c -> allow" '"permissionDecision":"allow"' "$(bash_json "$c" | sh "$CMD/push.sh")"
done
for c in 'echo "git push origin main"' 'git commit -m "merge main into feature"'; do
  verdict_absent "$c -> no push decision" '"ask"' "$(bash_json "$c" | sh "$CMD/push.sh")"
done
echo

echo "-- PreToolUse: commit guard, size and scope --"
lines src/big.ts && git add src/big.ts
verdict_absent "staged 600 lines + jq/mv, no commit -> no Large commit" '"ask"' \
  "$(bash_json 'jq ".a" package.json > f && mv f g' | sh "$CMD/commit.sh")"
verdict "staged 600 lines + cd && git commit -> ask" 'Large commit' \
  "$(bash_json 'cd . && git commit -m x' | sh "$CMD/commit.sh")"
clean_tree

lines src/utils/sum.ts
verdict "unstaged 600 lines + git commit -m -> allow (nothing staged)" \
  '"permissionDecision":"allow"' "$(bash_json 'git commit -m x' | sh "$CMD/commit.sh")"
verdict "unstaged 600 lines + git commit -am -> ask" 'Large commit' \
  "$(bash_json 'git commit -am x' | sh "$CMD/commit.sh")"
verdict "unstaged 600 lines + git add <path> && git commit -> ask" 'Large commit' \
  "$(bash_json 'git add src/utils/sum.ts && git commit -m x' | sh "$CMD/commit.sh")"
clean_tree

echo "// one more line" >> src/App.tsx && git add src
c=$(cat <<'CMD'
git commit -F - <<'EOF'
feat: merge the main parser into the feature

Remaining: nothing.
EOF
CMD
)
verdict "heredoc message mentioning main, feature branch -> allow" \
  '"permissionDecision":"allow"' "$(bash_json "$c" | sh "$CMD/commit.sh")"
clean_tree

# What `openspec archive` does: a plain filesystem move the index hasn't seen.
mkdir -p openspec/changes/demo && lines openspec/changes/demo/tasks.md
git add openspec && git -c user.email=t@example.com -c user.name=test commit -qm "add demo change"
mkdir -p openspec/changes/archive && mv openspec/changes/demo openspec/changes/archive/demo
verdict_absent "moved 600-line folder, git add -A dir && git commit -> no Large commit" \
  'Large commit' "$(bash_json 'git add -A openspec && git commit -m x' | sh "$CMD/commit.sh")"
clean_tree
git reset -q --keep HEAD~1

mkdir -p .claude && printf '{ "lockfile": "yarn.lock" }\n' > .claude/harness.json
lines lock.tmp && cat lock.tmp >> yarn.lock && rm lock.tmp
printf 'a\nb\nc\n' >> src/App.tsx && git add src yarn.lock
verdict "600-line lockfile change + 3 source lines -> allow" '"permissionDecision":"allow"' \
  "$(bash_json 'git commit -m x' | sh "$CMD/commit.sh")"
rm -f .claude/harness.json; clean_tree
echo

echo "-- PreToolUse: commits and refs through the GitHub API --"
for c in 'gh api repos/o/r/git/refs -f ref=refs/heads/x -f sha=abc' \
         'gh api -X PATCH repos/o/r/git/refs/heads/x -f sha=abc' \
         'gh api repos/o/r/git/commits -f message=x -f tree=abc'; do
  verdict "$c -> ask" 'bypasses local git hooks' "$(bash_json "$c" | sh "$CMD/ghapi.sh")"
done
for c in 'gh api repos/o/r/git/ref/heads/main --jq .object.sha' \
         'gh api repos/o/r/branches/main/protection' 'gh api repos/o/r/rulesets' \
         'gh api -X GET repos/o/r/git/refs -f per_page=100'; do
  verdict_absent "$c -> no ask" '"ask"' "$(bash_json "$c" | sh "$CMD/ghapi.sh")"
done
echo

echo "-- PreToolUse: unreadable command keeps the old, cautious behaviour --"
git checkout -q main
for g in commit merge push; do
  verdict "empty payload on main -> $g asks" '"permissionDecision":"ask"' \
    "$(echo '{}' | sh "$CMD/$g.sh")"
done
git checkout -q feature/test
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
# `coverage` must not catch a sibling that merely starts with the same word.
mkdir -p coverage-report && echo "<html>" > coverage-report/index.html
verdict "pattern is not a prefix match (coverage vs coverage-report/) -> allow" \
  '"permissionDecision":"allow"' \
  "$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/coverage-report/index.html"}}' "$REPO" \
     | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/ignore.sh")"
rm -rf coverage-report
verdict "Grep with no path -> allow" '"permissionDecision":"allow"' \
  "$(printf '{"tool_name":"Grep","tool_input":{"pattern":"x"}}' \
     | CLAUDE_PROJECT_DIR="$REPO" sh "$CMD/ignore.sh")"
verdict "absolute path outside the project, no matching part -> allow" \
  '"permissionDecision":"allow"' \
  "$(printf '{"tool_name":"Read","tool_input":{"file_path":"%s/elsewhere/src/x.ts"}}' "$WORK" \
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
