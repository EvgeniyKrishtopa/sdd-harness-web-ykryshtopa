#!/usr/bin/env bash
# Behaviour test for the deep-review risk prefilter in
# skills/code-review/references/deep-review.md.
#
# The prefilter is a shell block inside a Markdown reference, so nothing ran
# it until a real project did: in 0.10.3 a diff adding
# .github/workflows/ci.yml (token permissions, pull_request trigger) logged
# "no risk signals" and skipped the only security review in the plugin. This
# file extracts the block verbatim, points its range at a throwaway repo, and
# checks the verdict per diff -- so a signal that silently stops firing, or
# one that starts firing on every run, fails here instead of in a project.
#
# Run from anywhere:
#   bash tests/risk-prefilter.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DOC="$ROOT/skills/code-review/references/deep-review.md"

pass_count=0
fail_count=0

ok()  { printf '  [OK]   %s\n' "$1"; pass_count=$((pass_count + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail_count=$((fail_count + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== deep-review risk prefilter :: behaviour test =="
echo "Doc: $DOC"
echo

# The first ```bash block after "## The prefilter", with its placeholder
# range replaced by the base commit each case creates.
awk '/^## The prefilter/ {s=1} s && /^```bash/ {f=1; next} f && /^```/ {exit} f' "$DOC" \
  | sed 's|^range="<parent>\.\.HEAD".*|range="base..HEAD"|' > "$TMP/prefilter.sh"

if grep -q '^range="base\.\.HEAD"$' "$TMP/prefilter.sh"; then
  ok "extracted the prefilter block and its range line"
else
  bad "could not find the prefilter block or its range=\"<parent>..HEAD\" line in $DOC"
  echo; echo "Passed: $pass_count  Failed: $fail_count"; exit 1
fi

# new_repo -- a repo with one base commit, tagged `base`.
new_repo() {
  repo="$TMP/repo-$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  echo base > "$repo/base.txt"
  git -C "$repo" add -A && git -C "$repo" commit -qm base && git -C "$repo" tag base
}

# add_file <path> <content> -- adds and commits one file in the current repo.
add_file() {
  mkdir -p "$repo/$(dirname "$1")"
  printf '%s\n' "$2" > "$repo/$1"
  git -C "$repo" add -A && git -C "$repo" commit -qm "add $1"
}

run_prefilter() { (cd "$repo" && bash "$TMP/prefilter.sh"); }

# expect <case name> <expected first line> [expected filename]
expect() {
  out="$(run_prefilter)"
  first="$(printf '%s\n' "$out" | head -n 1)"
  if [ "$first" != "$2" ]; then
    bad "$1: expected '$2', got: $(printf '%s' "$out" | tr '\n' ' ')"
  elif [ -n "${3:-}" ] && ! printf '%s\n' "$out" | grep -qxF "$3"; then
    bad "$1: verdict '$2' but '$3' not listed: $(printf '%s' "$out" | tr '\n' ' ')"
  else
    ok "$1 -> $2"
  fi
}

echo "-- CI/CD paths fire --"

new_repo workflow
add_file .github/workflows/ci.yml 'on: pull_request
permissions:
  contents: read
jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@0123456789abcdef0123456789abcdef01234567'
expect "workflow-only diff" "risk=path" ".github/workflows/ci.yml"

new_repo local-action
add_file .github/actions/setup/action.yml 'runs:
  using: composite'
expect "local action" "risk=path" ".github/actions/setup/action.yml"

new_repo gitlab
add_file .gitlab-ci.yml 'test:
  script: npm test'
expect "GitLab CI config" "risk=path" ".gitlab-ci.yml"

new_repo dockerfile
add_file Dockerfile.prod 'FROM node:22-alpine'
expect "Dockerfile variant" "risk=path" "Dockerfile.prod"

new_repo vercel
add_file vercel.json '{ "headers": [] }'
expect "vercel.json" "risk=path" "vercel.json"

echo
echo "-- CI/CD content fires outside Markdown --"

new_repo script-token
add_file scripts/release.sh 'gh release create "$TAG" --repo "$REPO" # uses GITHUB_TOKEN'
expect "GITHUB_TOKEN in a script" "risk=content" "scripts/release.sh"

new_repo mdx
add_file src/pages/intro.mdx '<div dangerouslySetInnerHTML={{ __html: html }} />'
expect "risky JSX in .mdx (still scanned)" "risk=content" "src/pages/intro.mdx"

echo
echo "-- a test folder below the root is working code (0.12.0) --"

new_repo action-test
add_file .github/actions/test/action.yml 'runs:
  using: composite
  steps:
    - run: echo "${{ secrets.NPM_TOKEN }}"'
expect "local action in a test folder" "risk=path" ".github/actions/test/action.yml"

new_repo action-e2e
add_file .github/actions/e2e/action.yml 'runs:
  using: composite'
expect "local action in an e2e folder" "risk=path" ".github/actions/e2e/action.yml"

new_repo api-test-route
add_file src/app/api/test/route.ts 'import { execSync } from "node:child_process";
export function GET() { return new Response(execSync("ls").toString()); }'
expect "API route in a test folder" "risk=content" "src/app/api/test/route.ts"

echo
echo "-- does not fire --"

new_repo docs
add_file docs/guide.md '# Guide

How to run the app locally.'
expect "docs-only diff" "risk=none"

new_repo readme-prose
add_file README.md 'The release job reads GITHUB_TOKEN; set permissions: contents: write
and never use pull_request_target with secrets. on innerHTML too.'
expect "README prose naming CI signals (Markdown is not content-scanned)" "risk=none"

new_repo auth-docs-tests
add_file openspec/changes/add-login/proposal.md '# Login with session token'
add_file docs/auth/session.md 'The session cookie is HttpOnly.'
add_file src/auth/login.test.ts 'it("stores the jwt", () => { expect(localStorage.getItem("token")).toBe("x"); });'
add_file tests/e2e/login.spec.ts 'test("login", async () => {});'
expect "docs, spec and tests on sign-in only (0.12.0)" "risk=none"

new_repo src-test-setup
add_file src/test/setup.ts 'beforeEach(() => localStorage.clear());'
expect "test setup under src/test/ (content signals off for tests)" "risk=none"

new_repo root-tests
add_file e2e/login.spec.ts 'test("login", async () => {});'
add_file tests/auth.test.ts 'it("signs in", () => {});'
expect "tests in root e2e/ and tests/" "risk=none"

new_repo auth-source-with-tests
add_file src/auth/login.test.ts 'it("logs in", () => {});'
add_file src/auth/login.ts 'export const login = () => null;'
expect "the source next to its test still fires" "risk=path" "src/auth/login.ts"

new_repo component
add_file src/components/Button.tsx 'export function Button({ label }: { label: string }) {
  return <button type="button">{label}</button>;
}'
expect "ordinary component diff" "risk=none"

echo
echo "-- fails open --"

new_repo empty-range
expect "range with no changed files" "prefilter unavailable: git diff --name-only base..HEAD listed no files"

echo
echo "Passed: $pass_count  Failed: $fail_count"
[ "$fail_count" -eq 0 ]
