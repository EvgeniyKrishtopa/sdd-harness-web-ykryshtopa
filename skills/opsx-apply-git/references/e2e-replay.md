# Replaying recorded scenarios before push — step 3a

Referenced from `SKILL.md` §4 step 3a. Background:
`harness-audit/v0.11.0-planned/03-e2e-replay-before-push.txt`.

Recorded scenarios used to run only inside the next `web-qa`, which runs
once per change, on its last group, and only when the change touched the
interface. A change with no interface, or any middle group, never ran them,
so a broken flow could sit in `main` for weeks. This step runs them before
every push of a run, at 0 model tokens on the green path — the model only
comes in through `debug-loop`.

It runs after `code-review` and `harness-review` on purpose: their fixes are
new commits, and the replay must see the code that is about to be pushed.
Before anything else, note `pre_replay=$(git rev-parse HEAD)` — item 6 of
"The replay" reviews only what this step itself committed.

## Settings it reads

From `.claude/harness.json`: `tests.e2e.command` (default
`npx playwright test`), `tests.e2e.dir` (then the pre-0.11.0
`webQaScenariosDir`, then `tests/web-qa-scenarios` — call it `<dir>`),
`tests.e2e.externalTag` (default `@external`), `tests.e2e.replayBeforePush`,
`tests.e2e.preflight`, `tests.integration.healthCheck`, and `framework` for
the script below.

## Two sizes of run

- **This change's scenarios** — an ordinary run. Only scenarios tagged
  `@<change-slug>` (`web-qa` sets the tag when recording,
  `skills/web-qa/references/recording-rules.md` rule 5).
- **Affected scenarios** — the change's last run: after it, `tasks.md` has
  no unchecked task left, and the next stop is the merge into `main`. This
  change's scenarios plus every older one whose pages the change touched.
  Pick them with the plugin's script, over the **whole change's** diff, not
  this run's — earlier runs could have touched an old flow too:
  ```bash
  main=$(git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo origin/main)
  node "${CLAUDE_PLUGIN_ROOT}/skills/opsx-apply-git/scripts/affected-scenarios.mjs" \
    --base "$(git merge-base "$main" HEAD)" --dir "<dir>" --change "<change-slug>" \
    --framework "$(jq -r '.framework // empty' .claude/harness.json)"
  ```
  It prints `{scope, scopeReason, trigger, files}`. `scope` `affected` →
  run `files`. `scope` `full` → run the whole `<dir>`; the report names
  `scopeReason` and `trigger`, the changed file that decided it
  (`<file> -> <the file it reaches>` when that is an import away). When a
  guess would be needed, the script runs everything:
  - `no route structure` — not Next.js (a Vite app keeps its routes in
    code, even with a `src/pages/` or `app/` folder), or no `app/`/`pages/`;
  - `shared file changed` — a file every page depends on (root layout,
    middleware, `next.config.*`, a global stylesheet, `package.json`, a
    lockfile), or a file one of them imports;
  - `route handler changed` — a `route.*` handler or `pages/api/**`, or a
    file one imports: pages call it by URL, which no import shows;
  - `unmapped file changed` — a changed file that reaches no page
    (`tailwind.config.*`, a `public/` asset, a file nothing imports);
  - `import map failed` — no `typescript` package, or TypeScript 7, which
    dropped the JS API the script uses. The safe direction, not an error.

  Docs, `*.d.ts`, tests and files only tests import, and `.claude/`,
  `.husky/`, `.github/`, `openspec/` decide nothing. A scenario without a
  `// pages:` list, or with an empty one, is always in `files`; so is one
  that imports a changed file, such as a shared helper.

On early runs this change has no scenarios of its own yet (`web-qa` records
on the last group), so the ordinary run is skipped; old flows those runs
touched are caught by the last run's affected set, which sees the whole
change.

## When to skip (closed list, first match wins)

1. No `tests.e2e` block, or `replayBeforePush` is `false` →
   `e2e not configured`.
2. `<dir>` missing or holds no scenario file → `no recorded scenarios`.
3. An ordinary run and no file in `<dir>` carries `@<change-slug>` →
   `no scenarios for this change`. Never on the last run.
4. Every path in `git diff --name-only <parent>..HEAD` ends in `.md` →
   `docs only`. Do **not** use step 1's `trivialDiffPaths`: it holds `*.css`,
   `*.svg` and `public/**`, and a style change breaks flows (a button under a
   transparent layer, `display: none`). No line-count threshold either: one
   line in a component can break a flow.
5. `web-qa` ran in this run and ended passed (`clean`, or `confirmed` with
   its fix loop ending green), and every path in
   `git diff --name-only <the group commit web-qa's pass went into>..HEAD`
   ends in `.md` (or there is none) → `replayed by web-qa`. Compare from the
   group's commit, not from `web-qa` itself: `web-qa` runs before that
   commit, on the very code it then holds. A `code-review` fix after it is
   code `web-qa` never saw, so the replay runs.
6. Last run, and the script's `files` is empty → `no affected scenarios`.

Each skip writes one log line, `verdict` `skipped` (below), and goes on to
push.

## The replay

1. **Environment check.** `tests.e2e.preflight` set → `<runCmd> <preflight>`
   first. Non-zero → an environment failure, not an app one: tell the human
   in one line what is wrong with the environment, log `confirmed` with
   `failureKind` `environment`, do not push, do **not** start `debug-loop`.
2. **Run.** Always name `<dir>` or the script's files on the command line:
   without it Playwright takes `testDir` from its config and can run the
   project's other e2e tests, or miss the recorded ones. Both a path and
   `--grep` are regular expressions matched as substrings, so the tag needs
   a boundary — `@add-login` must not match `@add-login-v2`:
   ```bash
   # ordinary run
   <command> <dir> --grep "@<change-slug>(?![\w-])" --grep-invert "<exclude>"
   # last run, scope "affected"
   <command> <file-1> <file-2> … --grep-invert "<exclude>"
   # last run, scope "full"
   <command> <dir> --grep-invert "<exclude>"
   ```
   `<exclude>` is `(<externalTag>)(?![\w-])` from the settings — never type
   `@external` in yourself. When `tests.integration.healthCheck` is missing
   or fails, it is `(<externalTag>|@local-stack)(?![\w-])`, and the report
   says how many scenarios were left out, with the reason
   `local services down`. This step never starts a server: the config's
   `webServer` does, or reuses a running one.
3. **Tell the environment apart from the app** before calling anything a
   failure:
   - Output says `No tests found` → run `<command> <dir> --list`. It finds
     nothing either → `testDir` doesn't cover `<dir>`: an environment
     failure, one line — "testDir in playwright.config doesn't cover
     `<dir>` — fix the config". It does find tests → the filter left none
     (every matching one is external or local-stack): skip with
     `no scenarios for this change` (ordinary run) or
     `no affected scenarios` (last run).
   - `ECONNREFUSED` on the first navigation → an environment failure:
     "playwright.config has no webServer — start the app or add webServer".

   Either way: `failureKind` `environment`, no push, no `debug-loop` —
   there is nothing wrong in the code to fix.
4. **All passed** → log `clean`, go to push.
5. **Something failed** → the same as a `web-qa` failure: `debug-loop`,
   bounded by `maxFixAttempts`; each fix its own commit on the run's
   branch; after it, the project's typecheck/lint/tests again, then this
   replay again. A stale scenario (a renamed button, a changed flow) is the
   same kind of failure — never delete a scenario to turn it green.
   `maxFixAttempts` exhausted → report-only, as for `code-review`: every
   group is already committed, so there is no task line for a `blocked`
   marker. Do not push; report each attempt's hypothesis.
6. **Green after `debug-loop` fixes** → nobody has reviewed those commits:
   step 2's `code-review` ran before them. Run `code-review` again on
   `git diff $pre_replay..HEAD` only, and handle its findings as in step 2.
   If that fixes something in a new commit, replay once more (0 tokens);
   red → report-only, no push, no second round of `debug-loop`. Green →
   push. Green on the first replay → no commits, no second `code-review`.

## The log line

One line per step 3a, written once its outcome is final:

```bash
printf '%s\n' "$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --arg change "<change-slug>" --arg group "<group-number-or-range>" \
  --arg verdict "<clean|confirmed|skipped>" --arg skipReason "<reason, or empty>" \
  --argjson durationMs <ms> --argjson tokensTotal <0, or null after debug-loop> \
  --arg tokensNote "<empty, or why tokensTotal is null>" \
  --argjson fixIterations <n> --argjson escalatedToHuman <true|false> \
  --arg scope "<change|affected|full, empty when skipped>" \
  --arg scopeReason "<only for full>" --argjson scenarios <files run, 0 when skipped> \
  --arg failureKind "<app|environment, only for confirmed>" \
  '{ts:$ts,change:$change,group:$group,gate:"e2e-replay",verdict:$verdict,skipReason:$skipReason,durationMs:$durationMs,tokensTotal:$tokensTotal,tokensNote:$tokensNote,model:"",reviewConfidence:"",fixIterations:$fixIterations,escalatedToHuman:$escalatedToHuman,scope:$scope,scopeReason:$scopeReason,scenarios:$scenarios,failureKind:$failureKind}')" \
  >> .claude/harness-log.jsonl
```

`verdict` `confirmed` whenever a failure was found along the way, even if
`debug-loop` fixed it — the same rule as `web-qa`. `tokensTotal` is `0` when
`debug-loop` never ran: the replay is a shell command, and 0 is the truth.
After `debug-loop` it is `null` with a `tokensNote`; never `0`, which
`harness-stats` reads as a free run. `fixIterations` is `debug-loop`'s
attempt count, `escalatedToHuman` `true` only when it ran out. A failed log
write never blocks the step.
