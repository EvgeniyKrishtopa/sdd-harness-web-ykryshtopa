#!/usr/bin/env bash
# context7-trigger.sh -- the 0-token diff scan in
# skills/opsx-apply-git/references/context7-lookup.md, extracted as written
# and run against throwaway repos. 0.12.0: Markdown files and comment lines
# don't trigger a lookup.
#
# Usage: bash tests/context7-trigger.sh   (from the plugin root)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
DOC="$ROOT/skills/opsx-apply-git/references/context7-lookup.md"
pass=0; fail=0
ok()  { printf '  [PASS] %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail=$((fail + 1)); }

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
# The first ```bash block under "## The trigger", range pointed at a tag.
awk '/^## The trigger/{s=1} s && /^```bash$/{f=1;next} f && /^```$/{exit} f' "$DOC" \
  | sed 's|^range="<parent>\.\.HEAD"|range="base..HEAD"|' > "$WORK/scan.sh"
printf '\nprintf "%%s\\n" "$hits"\n' >> "$WORK/scan.sh"
grep -q '^range="base\.\.HEAD"' "$WORK/scan.sh" || { echo "could not extract the scan from $DOC"; exit 1; }

# scan <path> <content>: one commit on top of a base, prints the hits.
# Called inside $(...), so each call makes its own directory.
scan() {
  local repo; repo=$(mktemp -d "$WORK/r.XXXX")
  git -C "$repo" init -q; git -C "$repo" config user.email t@e; git -C "$repo" config user.name t
  echo base > "$repo/base"; git -C "$repo" add -A; git -C "$repo" commit -qm base; git -C "$repo" tag base
  mkdir -p "$repo/$(dirname "$1")"; printf '%s\n' "$2" > "$repo/$1"
  git -C "$repo" add -A; git -C "$repo" commit -qm change
  (cd "$repo" && bash "$WORK/scan.sh" | grep .)
}
fires() { if [ -n "$2" ]; then ok "$1"; else bad "$1 (no hit)"; fi; }
quiet() { if [ -z "$2" ]; then ok "$1"; else bad "$1 (hit: $2)"; fi; }

echo "-- code fires --"
fires "an import" "$(scan src/page.tsx 'import { useRouter } from "next/navigation";')"
fires "a name after code on the same line" "$(scan src/a.ts 'const x = 1; // next/navigation')"

echo "-- Markdown and comment lines don't --"
quiet "a README" "$(scan README.md 'We use next/navigation and useTransition.')"
quiet "a nested .md" "$(scan docs/guide/routing.md 'next/router is gone')"
quiet "a // comment" "$(scan src/a.ts '  // TODO: move to next/navigation')"
quiet "a /* comment" "$(scan src/a.ts '/* useTransition later */')"
quiet "a JSDoc line" "$(scan src/a.ts '   * @see next/headers')"
quiet "a JSX comment" "$(scan src/a.tsx '    {/* Suspense goes here */}')"

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
