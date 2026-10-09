# The dependency audit: plain command or a script with an allowlist (0.12.0)

Read from `references/git-hooks.md` step 4, before writing `<audit
command>` into `.husky/pre-push`.

## Why there is a choice

The plain audit command blocks every push while any high or critical
advisory is open — including one in a package nobody touched, with no fix
published yet. The only way past it is `--no-verify`, which skips the tests
too. The script keeps the audit blocking but lets the project record a known
advisory with a reason and an end date. When the date passes, the advisory
fails the push again, so an entry can't be forgotten.

## The question

Ask once (`AskUserQuestion`), unless `.claude/harness.json` already has
`depsAudit`:

- **Script with an allowlist** — `scripts/deps-audit.mjs` and
  `scripts/audit-allowlist.json` go into the project; the hook calls the
  script.
- **Plain audit command** — the hook calls the package manager's audit, as
  before 0.12.0.

Write the answer to `depsAudit` (`"script"` or `"plain"`) in Step 8.

## Script chosen

1. Copy `${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/deps-audit.mjs`
   to `scripts/deps-audit.mjs` as it is. The file exists already → leave it
   alone; the project owns it.
2. `scripts/audit-allowlist.json` missing → write `[]`. Never overwrite it:
   its entries are the project's decisions.
3. `<audit command>` in the hook becomes the script with the JSON form of
   the package manager's audit:
   - `npm` → `node scripts/deps-audit.mjs npm audit --json`
   - `pnpm` → `node scripts/deps-audit.mjs pnpm audit --json`
   - `yarn` 1.x → `node scripts/deps-audit.mjs yarn audit --json`
   - `yarn` 2.x or higher → `node scripts/deps-audit.mjs yarn npm audit --json`

   The script applies the high-or-above bar itself, so no level flag.
4. Report one line: what an entry looks like —
   `{"id": "GHSA-…", "reason": "…", "expires": "YYYY-MM-DD"}` — and that
   adding one is the project's decision, never the plugin's.

The script fails on: any high or critical advisory without a live entry, an
expired entry whose advisory is still reported, a broken allowlist, and a
report it can't read (an audit that didn't run is not a passed audit). It
lists entries whose advisory is no longer reported, so they can be removed.

## Regular audit — printed, never written

A vulnerability published after the last push shows up only on the next
push. Ask once whether to print a scheduled audit job template. Yes → print
it in the report: one job on a weekly schedule that installs dependencies
and runs the same `<audit command>` as the hook. Its first line says the
project owns this file. **Never write it**: not to `.github/workflows/`,
not anywhere else.
