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
4. Write `.husky/pre-push` in two parts. **First, always**, the block that
   lets a push carrying nothing but the harness log through untested —
   `opsx-apply-git` §4 pushes once more after committing the log under
   `.claude/harness-log/`, and re-running every test for a file no test
   reads doubles the wait for nothing. git hands the hook one line per
   pushed ref on stdin (Husky passes stdin through):
   ```sh
   # pre-push: a push that changes only the harness log is not tested
   only_log=yes
   while read -r _ local_sha _ remote_sha; do
     case "$local_sha" in *[!0]*) ;; *) continue ;; esac
     case "$remote_sha" in *[!0]*) ;; *) only_log=no; break ;; esac
     changed=$(git diff --name-only "$remote_sha" "$local_sha" 2>/dev/null) || { only_log=no; break; }
     if [ -n "$(printf '%s\n' "$changed" | grep -vxE '\.claude/harness-log(\.jsonl|/[^/]+\.jsonl)')" ]; then only_log=no; break; fi
   done
   if [ "$only_log" = yes ]; then
     echo "pre-push: only the harness log changed — tests skipped"
     exit 0
   fi
   ```
   A new branch (nothing on the remote yet) and a remote commit this clone
   doesn't have are always tested. A deleted branch is ignored. The log
   counts in both of its forms: the per-branch files under
   `.claude/harness-log/` (0.12.0) and the single `.claude/harness-log.jsonl`
   a project upgraded from an earlier version still has.

   **Then** the full coverage run and a blocking dependency-vulnerability
   audit, chained so a high-or-above severity finding blocks the push:
   ```sh
   <pm> test:coverage && <audit command>
   ```
   **If — and only if — the manifest names an integration script**
   (`tests.integration.script`, or the pre-0.11.0 `scripts.testIntegration`
   on a manifest not yet upgraded; optional, see
   `references/manifest-schema.md`), the second part is this instead:
   ```sh
   # pre-push: integration tests, with a note for opsx-apply-git's log
   note=.claude/.last-pre-push.json
   started=$(date +%s)
   outcome=not-reached
   int_started=
   write_note() {
     dur=0
     [ -n "$int_started" ] && dur=$(( ($(date +%s) - int_started) * 1000 ))
     printf '{"ts":%s,"integration":"%s","durationMs":%s}\n' "$started" "$outcome" "$dur" > "$note" 2>/dev/null || true
   }
   trap write_note EXIT
   trap 'exit 130' INT TERM
   <pm> test:coverage || exit 1
   if ! { <healthCheck>; } >/dev/null 2>&1; then
     outcome=services-down
     echo 'pre-push: local services are not running — start them with: <requires>' >&2
     exit 1
   fi
   outcome=fail
   int_started=$(date +%s)
   <pm> <integration script> || exit 1
   outcome=pass
   <audit command>
   ```
   `<healthCheck>` is `tests.integration.healthCheck` as written, inside
   the `{ …; }`: without it a user's compound check (`a && b`, `a; b`) is
   judged wrong both ways, and a `$(…)` in it, like the Compose row's,
   prints its errors past the redirect;
   `<requires>` is `tests.integration.requires` with each `'` written as
   `'\''`. No `healthCheck` → leave out the whole `if … fi` block. The
   message is exactly one line: the human should see which command to run,
   not a stack.

   Order matters and this is the order: coverage, the services check,
   integration, audit. The integration run is the slow one — a project puts
   its tests behind a second script precisely because they need a database
   or a running server — so the faster check gets to fail first, and the
   services are checked right before the link that needs them.

   The note (`.claude/.last-pre-push.json`) is written on every exit — a
   passed run, a failed link, Ctrl+C — so `opsx-apply-git` §4 can log how
   the integration tests ended (`pass`, `fail`, `services-down`, or
   `not-reached` when coverage failed first) without the hook touching the
   tracked log, which would leave the working tree dirty after every push.
   Add `.claude/.last-pre-push.json` to the project's `.gitignore` (append
   the line if missing). A push the first block lets through writes no note.

   No integration script in the manifest (the common case) → the two-link
   chain and no note; the integration paragraphs don't apply. There is no
   "skip the integration run" flag: a project that finds the push too slow
   leaves the key unset, rather than carrying a switch that gets turned off
   once and never back on.
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
