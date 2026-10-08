#!/usr/bin/env bash
# Behaviour test for skills/opsx-apply-git/scripts/affected-scenarios.mjs --
# the import map that picks which recorded scenarios the replay before push
# runs on a change's last run (references/e2e-replay.md).
#
# Builds a throwaway Next.js-shaped project: three pages (/login inside the
# route group (auth), /profile, /cart), a component shared by two of them, a
# component only /login imports, a CSS module, a dynamic route and one
# Pages Router page, plus scenarios with and without a page list. Each case
# commits one change and checks the scope and the picked files. A few cases
# reshape the project into a Vite app: those must run every scenario.
#
# The import map runs the project's own `typescript` package; this test
# installs typescript@6.0.3 once into a temp directory. Offline, the cases
# that need it are reported as SKIP; the cases that need no TypeScript still
# run.
#
# Run from anywhere:
#   bash tests/affected-scenarios.sh
set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/skills/opsx-apply-git/scripts/affected-scenarios.mjs"

pass_count=0
fail_count=0
skip_count=0

ok()   { printf '  [OK]   %s\n' "$1"; pass_count=$((pass_count + 1)); }
bad()  { printf '  [FAIL] %s\n' "$1"; fail_count=$((fail_count + 1)); }
skip() { printf '  [SKIP] %s\n' "$1"; skip_count=$((skip_count + 1)); }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

echo "== affected-scenarios.mjs :: behaviour test =="
echo "Script: $SCRIPT"
echo

ts_dir="$TMP/ts"
mkdir -p "$ts_dir"
if (cd "$ts_dir" && npm install --silent --no-audit --no-fund --no-save typescript@6.0.3 >/dev/null 2>&1) \
   && [ -f "$ts_dir/node_modules/typescript/package.json" ]; then
  have_ts=true
else
  have_ts=false
  echo "  (typescript@6.0.3 could not be installed -- import-map cases will SKIP)"
fi

# put <path> <content> -- writes a file in the current repo.
put() { mkdir -p "$repo/$(dirname "$1")"; printf '%s\n' "$2" > "$repo/$1"; }
commit() { git -C "$repo" add -A && git -C "$repo" commit -qm "$1"; }

# new_next_repo <name> -- the project above, committed and tagged `base`.
new_next_repo() {
  repo="$TMP/repo-$1"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email t@example.com
  git -C "$repo" config user.name t
  put package.json '{ "name": "demo", "private": true }'
  put next.config.js 'module.exports = {};'
  put tsconfig.json '{ "compilerOptions": { "jsx": "preserve", "moduleResolution": "bundler", "module": "esnext", "baseUrl": ".", "paths": { "@/*": ["./*"] } } }'
  put app/layout.tsx 'import "./globals.css"; export default function L({ children }) { return children; }'
  put app/globals.css 'body { margin: 0; }'
  put 'app/(auth)/login/page.tsx' 'import { LoginForm } from "@/components/LoginForm"; import { Button } from "@/components/Button"; export default function P() { return <LoginForm />; }'
  put app/profile/page.tsx 'import { Avatar } from "../../components/Avatar"; import s from "@/styles/card.module.css"; export default function P() { return <Avatar />; }'
  put app/profile/layout.tsx 'export default function L({ children }) { return children; }'
  put 'app/(shop)/cart/page.tsx' 'import { Button } from "@/components/Button"; export default function P() { return <Button />; }'
  put 'app/items/[id]/page.tsx' 'import { format } from "@/lib/format"; export default function P() { return format(1); }'
  put pages/about.tsx 'export default function A() { return null; }'
  put components/LoginForm.tsx 'export function LoginForm() { return null; }'
  put components/Button.tsx 'export function Button() { return null; }'
  put components/Avatar.tsx 'export function Avatar() { return null; }'
  put styles/card.module.css '.card { padding: 1px; }'
  put lib/format.ts 'export const format = (n: number) => String(n);'
  put lib/unused.ts 'export const unused = 1;'
  put middleware.ts 'export function middleware() {}'
  put tests/web-qa-scenarios/login.spec.ts "// pages: /login
test('sign in', { tag: ['@old-change'] }, async () => {});"
  put tests/web-qa-scenarios/profile.spec.ts "// pages: /profile
test('profile', { tag: ['@old-change'] }, async () => {});"
  put tests/web-qa-scenarios/cart.spec.ts "// pages: /cart?step=1
test('cart', { tag: ['@old-change'] }, async () => {});"
  put tests/web-qa-scenarios/item.spec.ts "// pages: http://localhost:3000/items/42/
test('item', { tag: ['@old-change'] }, async () => {});"
  put tests/web-qa-scenarios/about.spec.ts "// pages: /about
test('about', { tag: ['@old-change'] }, async () => {});"
  put tests/web-qa-scenarios/legacy.spec.ts "test('recorded before 0.11.0', async () => {});"
  put tests/web-qa-scenarios/current.spec.ts "// pages: /nowhere
test('this change', { tag: ['@add-thing'] }, async () => {});"
  put tests/web-qa-scenarios/later.spec.ts "// pages: /nowhere
test('a later change', { tag: ['@add-thing-v2'] }, async () => {});"
  if [ "${2:-}" != "no-ts" ] && $have_ts; then
    mkdir -p "$repo/node_modules"
    ln -s "$ts_dir/node_modules/typescript" "$repo/node_modules/typescript"
  fi
  printf 'node_modules\n' > "$repo/.gitignore"
  commit base && git -C "$repo" tag base
}

# FW is the manifest's `framework` the call passes; unset means Next.js.
run() { (cd "$repo" && node "$SCRIPT" --base base --dir tests/web-qa-scenarios --change add-thing --framework "${FW-next}"); }

# field <json> <scope|scopeReason|files>
field() {
  node -e 'const o = JSON.parse(process.argv[1]); const v = o[process.argv[2]];
    console.log(Array.isArray(v) ? v.map((f) => f.split("/").pop().replace(/\.spec\.ts$/, "")).sort().join(" ") : v);' "$1" "$2"
}

# expect <case> <scope> <scopeReason> <space-separated scenario names, sorted>
expect() {
  out="$(run)"
  scope="$(field "$out" scope)"; reason="$(field "$out" scopeReason)"; files="$(field "$out" files)"
  if [ "$scope" = "$2" ] && [ "$reason" = "$3" ] && [ "$files" = "$4" ]; then
    ok "$1 -> $2${3:+ ($3)}: $4"
  else
    bad "$1: expected $2 '$3' [$4], got $scope '$reason' [$files]"
  fi
}

ALL="about cart current item later legacy login profile"
ALWAYS="current legacy"   # tagged with this change; no page list

echo "-- the import map --"
if $have_ts; then
  new_next_repo login
  put components/LoginForm.tsx 'export function LoginForm() { return "changed"; }'; commit login
  expect "LoginForm (only /login imports it, page inside group (auth))" affected "" "current legacy login"

  new_next_repo button
  put components/Button.tsx 'export function Button() { return "changed"; }'; commit button
  expect "Button (shared by /login and /cart)" affected "" "cart current legacy login"

  new_next_repo css-module
  put styles/card.module.css '.card { padding: 2px; }'; commit css
  expect "CSS module through a tsconfig paths alias" affected "" "current legacy profile"

  new_next_repo layout
  put app/profile/layout.tsx 'export default function L({ children }) { return <main>{children}</main>; }'; commit layout
  expect "a nested layout touches its subtree" affected "" "current legacy profile"

  new_next_repo dynamic
  put lib/format.ts 'export const format = (n: number) => `#${n}`;'; commit dynamic
  expect "dynamic segment [id], a page list given as a full URL" affected "" "current item legacy"

  new_next_repo pages-router
  put pages/about.tsx 'export default function A() { return "about"; }'; commit about
  expect "Pages Router page" affected "" "about current legacy"

  new_next_repo nothing
  put lib/unused.ts 'export const unused = 2;'; commit unused
  expect "a file no page imports" affected "" "$ALWAYS"

  new_next_repo scenario-edit
  put tests/web-qa-scenarios/cart.spec.ts "// pages: /cart
test('cart, edited', { tag: ['@old-change'] }, async () => {});"; commit scenario
  expect "an edited scenario file runs itself" affected "" "cart current legacy"

  new_next_repo empty
  rm "$repo/tests/web-qa-scenarios/legacy.spec.ts" "$repo/tests/web-qa-scenarios/current.spec.ts"; commit trim
  git -C "$repo" tag -f base >/dev/null
  put lib/unused.ts 'export const unused = 3;'; commit unused
  expect "nothing touched, nothing of this change" affected "" ""
else
  skip "import-map cases (no typescript@6.0.3)"
fi

echo "-- run everything --"
new_next_repo globals
put app/globals.css 'body { margin: 1px; }'; commit globals
expect "globals.css" full "shared file changed" "$ALL"

new_next_repo middleware
put middleware.ts 'export function middleware() { return 1; }'; commit mw
expect "middleware.ts" full "shared file changed" "$ALL"

new_next_repo root-layout
put app/layout.tsx 'export default function L({ children }) { return <body>{children}</body>; }'; commit rl
expect "root app/layout.tsx" full "shared file changed" "$ALL"

new_next_repo no-ts no-ts
put components/LoginForm.tsx 'export function LoginForm() { return 1; }'; commit l
expect "no typescript package" full "import map failed" "$ALL"

new_next_repo ts7 no-ts
mkdir -p "$repo/node_modules/typescript"
printf '{ "name": "typescript", "version": "7.0.2", "main": "index.js" }\n' > "$repo/node_modules/typescript/package.json"
printf 'module.exports = { version: "7.0.2" };\n' > "$repo/node_modules/typescript/index.js"
put components/LoginForm.tsx 'export function LoginForm() { return 1; }'; commit l
expect "typescript 7 (no preProcessFile)" full "import map failed" "$ALL"

new_next_repo next-no-routes no-ts
git -C "$repo" rm -rq app pages next.config.js && commit "no route folders"
git -C "$repo" tag -f base >/dev/null
put src/main.ts 'export const x = 1;'; commit main
expect "Next.js manifest, no app/ or pages/" full "no route structure" "$ALL"

new_next_repo vite-pages
git -C "$repo" rm -rq app pages next.config.js && commit "now a Vite app"
put vite.config.ts 'export default {};'
put src/pages/LoginPage.tsx 'import { LoginForm } from "../components/LoginForm"; export function LoginPage() { return LoginForm; }'
put src/components/LoginForm.tsx 'export function LoginForm() { return null; }'; commit "src/pages"
git -C "$repo" tag -f base >/dev/null
put src/components/LoginForm.tsx 'export function LoginForm() { return "changed"; }'; commit l
FW=vite
expect "Vite app with src/pages/" full "no route structure" "$ALL"

new_next_repo react-router
git -C "$repo" rm -rq app pages next.config.js && commit "now React Router 7"
put vite.config.ts 'export default {};'
put app/root.tsx 'export default function Root() { return null; }'
put app/routes/login.tsx 'import { LoginForm } from "../components/LoginForm"; export default function Login() { return LoginForm; }'
put app/components/LoginForm.tsx 'export function LoginForm() { return null; }'; commit "app/routes"
git -C "$repo" tag -f base >/dev/null
put app/components/LoginForm.tsx 'export function LoginForm() { return "changed"; }'; commit l
expect "React Router 7 app with app/routes/" full "no route structure" "$ALL"

new_next_repo no-framework
put components/LoginForm.tsx 'export function LoginForm() { return 1; }'; commit l
FW=
expect "no framework in the manifest" full "no route structure" "$ALL"
unset FW

echo "-- usage --"
if (cd "$TMP" && node "$SCRIPT" --dir x >/dev/null 2>&1); then
  bad "missing --base/--change should exit non-zero"
else
  [ "$(cd "$TMP" && node "$SCRIPT" --dir x >/dev/null 2>&1; echo $?)" = "2" ] \
    && ok "missing arguments -> exit 2" || bad "missing arguments: exit code is not 2"
fi

echo
echo "Passed: $pass_count  Failed: $fail_count  Skipped: $skip_count"
[ "$fail_count" -eq 0 ]
