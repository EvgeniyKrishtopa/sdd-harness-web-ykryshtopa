# Step 3 — installing the native git hooks

Why these exist alongside this plugin's Claude Code hooks: `hooks/hooks.json`
only fires when **Claude itself** runs `git commit`/`git push` through the
Bash tool. It does nothing when the human commits or pushes directly from a
terminal with no agent involved. Real git hooks close that gap, so bad
commits and pushes are blocked regardless of who or what is committing.

The split by cost is deliberate. This harness commits once per `tasks.md`
group (`opsx-apply-git` §3), so a full `test:coverage` run on every
`pre-commit` turns into minutes of wait on every group — multiplied across a
whole change. `pre-commit` stays fast (typecheck + lint + lint-staged); the
full coverage run moves to `pre-push`, where it runs once per push instead
of once per commit.

## The procedure

1. If Husky and `lint-staged` aren't already devDependencies, install both
   (`yarn add -D husky lint-staged` / `npm install -D husky lint-staged` /
   `pnpm add -D husky lint-staged`) and run Husky's init (`npx husky init`).
2. Write `.husky/pre-commit` with the detected package manager's commands,
   chained so any failure blocks the commit:
   ```
   <pm> typecheck && <pm> lint && npx lint-staged
   ```
   (e.g. `yarn typecheck && yarn lint && npx lint-staged`, or the npm/pnpm
   equivalents — use whatever script names actually exist in this project's
   `package.json`; don't invent script names that aren't there, ask the user
   if the mapping isn't obvious.) No test run here — that's `pre-push`,
   below. Step 8b runs both of these names for real and stops the whole
   setup if either doesn't resolve, so a wrong guess here is caught during
   setup rather than on the user's first commit.
3. Configure `lint-staged` — in `package.json`'s `"lint-staged"` key, or a
   `.lintstagedrc.json` if the project already has one of those instead —
   to run the project's lint/format tooling against staged files only, e.g.
   for ESLint: `{"*.{ts,tsx}": "eslint --fix"}`. This is what actually keeps
   `pre-commit` fast: `<pm> lint` above still runs the full project-wide
   lint as a correctness gate, while `lint-staged` auto-fixes and re-stages
   only the files this commit actually touches — ask the user for the exact
   glob/command if the project's lint tooling isn't obvious from
   `package.json`.
4. Write `.husky/pre-push` with the full coverage run, then a blocking
   dependency-vulnerability audit, chained the same way as `pre-commit`
   above so a high-or-above severity finding blocks the push:
   ```
   <pm> test:coverage && <audit command>
   ```
   **If — and only if — the manifest has a `scripts.testIntegration`**
   (optional, see `references/manifest-schema.md`), chain that project's
   integration-test command as a middle link:
   ```
   <pm> test:coverage && <pm> test:integration && <audit command>
   ```
   Order matters and this is the order: coverage, integration, audit. The
   integration run is the slow one — a project puts its tests behind a
   second script precisely because they need a database or a running
   server — so the faster check gets to fail first, and the audit stays
   last where it already was. No `scripts.testIntegration` in the manifest
   (the common case) → write the two-link chain above and nothing else;
   this whole paragraph doesn't apply. There is no "skip the integration
   run" flag: a project that finds the push too slow leaves the key unset,
   rather than carrying a switch that gets turned off once and never back
   on.
   The audit command's spelling depends on the detected package manager —
   and, for yarn, on its major version, since the command changed between
   yarn 1 (Classic) and yarn 2+ (Berry):
   - `npm` → `npm audit --audit-level=high`
   - `pnpm` → `pnpm audit --audit-level high`
   - `yarn` → run `yarn --version` to tell which spelling applies: `1.x` →
     `yarn audit --level high`; `2.x` or higher → `yarn npm audit --severity high`

   Do not add `<pm> outdated` alongside the audit — it reports version drift,
   not vulnerabilities, and would leave the hook permanently red on any
   stale minor version. A check that's always red trains whoever runs it to
   ignore the whole hook, which defeats the audit it sits next to.
5. Do not overwrite an existing `.husky/pre-commit` or `.husky/pre-push`
   that already has content — read each first, and only append/merge the
   missing checks in, the same "never clobber existing config" rule used
   for merges later in this skill.
6. Confirm both hooks are executable (`chmod +x .husky/pre-commit
   .husky/pre-push` if needed).
