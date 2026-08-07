# Step 8b — proving the toolchain actually runs

## Why this step exists at all

Everything up to Step 8 has *detected* a toolchain. Nothing has *run* it.
Those script names are not decoration: Step 3 already wrote them into
`.husky/pre-commit`, and this plugin's `Stop` hook builds
`<runCmd> <scripts.typecheck>` straight out of the manifest. If a project
calls its script `type-check`, `tsc`, or `types` — all more common than
`typecheck` — then `pre-commit` fails on every single commit with "script not
found", and the `Stop` hook reports the package manager's complaint as if it
were a type error. Neither failure surfaces during setup. Both surface on the
first real task group, by which point the cause is three steps back.

Step 3 and Step 8 both already say "don't invent script names, ask the user."
That instruction was in 0.1.0 too, and the bug shipped anyway. An instruction
to be careful is not a check. This step is the check: four commands, once in
a repository's lifetime.

Run it in both first-install and upgrade mode, on a clean tree (if the tree
is dirty, say so and ask the user to commit or stash first — a lint failure
from the user's own uncommitted work would be blamed on the harness).

## 1. The keys exist

For each of `scripts.typecheck`, `scripts.lint`, and `scripts.testCoverage`,
confirm the name in the manifest is a real key in `package.json`:

```bash
for key in typecheck lint testCoverage; do
  name="$(jq -r --arg k "$key" '.scripts[$k]' .claude/harness.json)"
  jq -e --arg n "$name" '.scripts[$n]' package.json >/dev/null \
    || echo "MISSING: harness.json scripts.$key = \"$name\" is not in package.json"
done
```

Anything missing: stop and ask the user which script actually does that job
(offer the closest matches from `jq -r '.scripts | keys[]' package.json`). If
they name one, correct **both** `.claude/harness.json` and the `.husky/` hook
that embeds it — the two hold the same name in two places, and fixing one
leaves the other broken. If the project genuinely has no such script, that is
a real gap in the project, not something to paper over with a guess: say so
and stop.

## 2. Typecheck and lint pass

Run `<runCmd> <scripts.typecheck>` and `<runCmd> <scripts.lint>`. Both must
exit 0. A non-zero exit on a clean tree means this harness would block the
user's every commit from the moment it is installed — via
`.husky/pre-commit`, which chains exactly these two. Report which one failed
and its output, and stop. Don't offer to relax the hook: the hook is correct,
the repository isn't green.

## 3. The tests run *and* at least one passes

Run `<runCmd> <scripts.testCoverage>`. Read the count, don't just read the
exit code: Vitest and Jest both exit 1 on zero matched tests by default, but
`--passWithNoTests` flips that to 0, and it is common enough in starter
templates and CI scripts to be worth not trusting. A green exit from a runner
that matched nothing is an empty `pre-push`, not a passing one. Confirm from
the output that at least one test actually passed; the format follows the
detected `testRunner` (Vitest: `Tests  N passed`; Jest: `Tests:  N passed`),
and "No test files found" / "0 total" is a failure of this step. Report it as
such and stop — a project with no tests can still use the rest of the
harness, but the user should decide that knowingly rather than discover it
when Gate 5 reviews coverage that was never collected.

## 4. Any of the three not satisfied → stop the whole run

Name what didn't match, and leave `harnessVersion` and
`toolchainVerifiedAt` unwritten. The repository isn't configured, so nothing
should claim it is: an unwritten version means the next run comes back
through Step 0's upgrade branch rather than skipping as already-current.

Say one more thing before stopping, if the run stopped at item 1 with no
correct script name to substitute: `.claude/harness.json` still holds the
name that doesn't resolve, and this plugin's `Stop` hook reads
`scripts.typecheck` from it on every turn regardless of whether the repo was
ever verified. Until the user adds the script or corrects the manifest by
hand, that hook will keep reporting a "script not found" as though it were a
type error. The user needs to know that, because stopping here doesn't undo
it.

## 5. All three satisfied → write both remaining manifest keys

```json
{ "harnessVersion": "<plugin version from Step 0>", "toolchainVerifiedAt": "2026-08-01T12:00:00Z" }
```

`toolchainVerifiedAt` is an ISO-8601 UTC timestamp (`date -u
+%Y-%m-%dT%H:%M:%SZ`) — the shape above is not a value to copy. It is what
lets a later upgrade run, and Gate 6, tell "these commands were proven to
work" from "these names were assumed to be right", which is the whole
difference this step exists to record.
