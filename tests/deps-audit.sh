#!/usr/bin/env bash
# deps-audit.sh -- skills/init-harness/references/deps-audit.mjs, the audit
# script init-harness offers for .husky/pre-push (0.12.0). The reports below
# are real output of npm 11, pnpm 11, yarn 1.22 and yarn 4 on a project with
# minimist@1.2.5 (GHSA-xvch-5gv4-984h), trimmed to the fields that matter.
#
# Usage: bash tests/deps-audit.sh   (from the plugin root)
set -u

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
A="$ROOT/skills/init-harness/references/deps-audit.mjs"
pass=0; fail=0
ok()  { printf '  [PASS] %s\n' "$1"; pass=$((pass + 1)); }
bad() { printf '  [FAIL] %s\n' "$1"; fail=$((fail + 1)); }

command -v node >/dev/null 2>&1 || { echo "node is required"; exit 1; }
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/scripts"; cd "$WORK" || exit 1

cat > npm.json <<'EOF'
{"auditReportVersion":2,"vulnerabilities":{"minimist":{"name":"minimist","severity":"critical","isDirect":true,"via":[{"source":1097678,"name":"minimist","dependency":"minimist","title":"Prototype Pollution in minimist","url":"https://github.com/advisories/GHSA-xvch-5gv4-984h","severity":"critical","range":">=1.0.0 <1.2.6"}],"effects":[],"range":"1.0.0 - 1.2.5","nodes":["node_modules/minimist"],"fixAvailable":{"name":"minimist","version":"1.2.8","isSemVerMajor":false}}},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":1,"total":1}}}
EOF
cat > pnpm.json <<'EOF'
{"advisories":{"1097678":{"id":1097678,"title":"Prototype Pollution in minimist","module_name":"minimist","vulnerable_versions":">=1.0.0 <1.2.6","patched_versions":">=1.2.6","severity":"critical","cwe":"CWE-1321","github_advisory_id":"GHSA-xvch-5gv4-984h","url":"https://github.com/advisories/GHSA-xvch-5gv4-984h"}},"metadata":{"vulnerabilities":{"info":0,"low":0,"moderate":0,"high":0,"critical":1}}}
EOF
cat > yarn4.ndjson <<'EOF'
{"value":"minimist","children":{"ID":1097678,"Issue":"Prototype Pollution in minimist","URL":"https://github.com/advisories/GHSA-xvch-5gv4-984h","Severity":"critical","Vulnerable Versions":">=1.0.0 <1.2.6","Tree Versions":["1.2.5"],"Dependents":["t@workspace:."]}}
EOF
cat > yarn1.ndjson <<'EOF'
{"type":"warning","data":"package.json: No license field"}
{"type":"auditAdvisory","data":{"resolution":{"id":1097678,"path":"minimist","dev":false,"optional":false,"bundled":false},"advisory":{"id":1097678,"title":"Prototype Pollution in minimist","module_name":"minimist","severity":"critical","github_advisory_id":"GHSA-xvch-5gv4-984h","url":"https://github.com/advisories/GHSA-xvch-5gv4-984h"}}}
EOF
cat > twice.json <<'EOF'
{"a":{"severity":"moderate","url":"https://github.com/advisories/GHSA-dddd-eeee-ffff"},"b":{"severity":"high","url":"https://github.com/advisories/GHSA-dddd-eeee-ffff"}}
EOF
cat > moderate.json <<'EOF'
{"auditReportVersion":2,"vulnerabilities":{"x":{"name":"x","severity":"moderate","via":[{"name":"x","url":"https://github.com/advisories/GHSA-aaaa-bbbb-cccc","severity":"moderate"}]}},"metadata":{}}
EOF
echo '{"auditReportVersion":2,"vulnerabilities":{},"metadata":{"vulnerabilities":{"total":0}}}' > clean.json

# The audit command exits non-zero when it finds something; mimic that.
audit() { node "$A" sh -c "cat $1; exit $2" > out 2>&1; echo $? > code; }
code() { cat code; }
expect() { # name, wanted exit code, text the output must contain
  if [ "$(code)" = "$2" ] && grep -qF -- "$3" out; then ok "$1"; else bad "$1 (exit $(code), output: $(tr '\n' '|' < out))"; fi
}
allow() { printf '%s\n' "$1" > scripts/audit-allowlist.json; }

echo "-- no allowlist: a critical advisory fails, for every package manager --"
for r in npm.json pnpm.json yarn1.ndjson yarn4.ndjson; do
  audit "$r" 1; expect "$r fails and names the advisory" 1 "GHSA-XVCH-5GV4-984H (critical"
done

echo "-- the same advisory seen as moderate and as high: the high one counts --"
audit twice.json 1; expect "blocking severity wins" 1 "GHSA-DDDD-EEEE-FFFF (high"

echo "-- a clean report and a moderate-only report pass --"
audit clean.json 0; expect "clean passes" 0 "no high or critical advisory"
audit moderate.json 1; expect "moderate only passes" 0 "no high or critical advisory"

echo "-- a live entry lets it through, with its reason --"
allow '[{"id":"GHSA-xvch-5gv4-984h","reason":"dev-only CLI parser","expires":"2999-01-01"}]'
audit npm.json 1; expect "allowed until the date" 0 "allowed until 2999-01-01: dev-only CLI parser"

echo "-- an expired entry fails the audit again --"
allow '[{"id":"GHSA-xvch-5gv4-984h","reason":"dev-only CLI parser","expires":"2020-01-01"}]'
audit npm.json 1; expect "expired entry fails" 1 "allowlist entry expired 2020-01-01"

echo "-- an entry nobody reports any more is listed for removal --"
allow '[{"id":"GHSA-zzzz-zzzz-zzzz","reason":"old","expires":"2999-01-01"}]'
audit clean.json 0; expect "stale entry listed, audit passes" 0 "GHSA-ZZZZ-ZZZZ-ZZZZ is no longer reported"

echo "-- a broken allowlist entry fails loudly --"
allow '[{"id":"GHSA-xvch-5gv4-984h","expires":"2999-01-01"}]'
audit clean.json 0; expect "entry without a reason fails" 1 'needs "id" (GHSA-...), "reason" and "expires"'
allow '{}'
audit clean.json 0; expect "allowlist that is not an array fails" 1 "must be a JSON array"
allow 'not json'
audit clean.json 0; expect "unreadable allowlist fails" 1 "cannot read scripts/audit-allowlist.json"
allow '[]'

echo "-- an audit whose report can't be read is not a pass --"
printf 'npm error network request failed\n' > broken.txt
audit broken.txt 1; expect "unreadable report fails" 1 "its report could not be read"
audit clean.json 2; expect "empty report with a failed exit fails" 1 "its report could not be read"
if node "$A" > out 2>&1; then bad "no command accepted"; else ok "no command fails"; fi
if node "$A" no-such-audit-command-xyz > out 2>&1; then bad "missing command accepted"; else ok "missing command fails"; fi

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
