# Step 1b — which test layers this project can have, and what to offer

Read this from Step 1, after `references/stack-detection.md`. It decides the
optional `tests` block of `.claude/harness.json`
(`references/manifest-schema.md`). One rule holds for the whole file:
**find and offer, never add silently.** At most one question per layer, and
only when that layer's sign is found. A "no" leaves the repository exactly
as it was. Installing a package is the human's job (`permissions.deny`
blocks every install command).

A project with neither sign below gets no question from this file at all,
and no `tests` block: it behaves exactly as it did in 0.10.6.

In upgrade mode, skip a layer whose half of `tests` is already there — the
manifest answers it (`references/upgrade-mode.md`).

## Integration layer

**Sign: a local service this repository can start.**

| Found | `requires` | `healthCheck` |
| --- | --- | --- |
| `supabase/config.toml` | `supabase start` | `supabase status` |
| `docker-compose.yml` / `compose.yaml` with a database service (image `postgres`, `mysql`, `mongo`, `redis`) | `docker compose up -d` | `test -n "$(docker compose ps --status running -q <service>)"` |

The Compose check is wrapped in `test -n` on purpose: `docker compose ps
-q` exits 0 with empty output when nothing runs, so the bare command would
always pass. `supabase status` reports a stack that isn't started as an
error; confirm its exit code on the project's own CLI version once before
writing the key, not from memory.

Then, by what the project already has:

- **An integration script exists** (`stack-detection.md` lists the names to
  look for) → write it to `tests.integration.script`, no question, as
  before. If a sign was also found, offer `requires` and `healthCheck` from
  the table in one question.
- **No script, sign found** → one question offering the whole layer:
  - a `test:integration` script in `package.json`;
  - for Vitest, a separate `vitest.integration.config.ts` with
    `test.include: ['**/*.integration.test.ts']`, run as
    `vitest run --config vitest.integration.config.ts --passWithNoTests`;
  - the same pattern excluded from the main config so `<pm> test` doesn't
    run them — `exclude: [...configDefaults.exclude,
    '**/*.integration.test.ts']`, because a plain `exclude` replaces
    Vitest's defaults and starts collecting `node_modules`. Show the diff of
    the main config before writing it;
  - for Jest, the same through `testMatch` and a second config;
  - `requires` and `healthCheck` from the table.

  For Supabase, the config and its global setup come from
  `references/local-stack-profile.md` section 2 — it checks the services
  are up and refuses any address that isn't local.

  `--passWithNoTests` is deliberate here and nowhere else: the layer is
  new and has no tests yet, and an empty layer must not block every push
  until the first one lands. Step 8b reads this run's script with that in
  mind (`references/toolchain-proof.md`).
- **No script, no sign** → ask nothing, write nothing.

The integration tests themselves take the service's address and keys from
the local stack's own output (`supabase status -o env`), never from the
project's `.env*` files or the app's `process.env`.

## End-to-end layer

**Sign: `@playwright/test` in `devDependencies`.** Absent → offer nothing;
say one line in the report: `web-qa` offers to install it when it records
the first scenario, as it does today.

Present → one question: turn on the replay of recorded scenarios before
push. Yes → write `tests.e2e` with `dir` (default
`tests/web-qa-scenarios`), `command: "npx playwright test"`,
`externalTag: "@external"`, and `replayBeforePush: true`. Never write
`preflight` here: no detection rule for an environment-check script exists
yet, and a guessed script name is the one thing this skill never writes. No → no
`tests.e2e` block; the replay stays off.

The same question covers the Playwright config:

- **No `playwright.config.*`** → offer one with `testDir` pointing at the
  scenarios directory, `grepInvert: /@external/`, and a `webServer` with
  `reuseExistingServer: true`. On Next.js, `webServer.command` is the
  project's real build and start scripts (`<pm> build && <pm> start`) when
  the build passes in reasonable time; otherwise its `dev` script, and the
  report says so — a dev server makes replays flakier.
- **A config exists** → never rewrite it. List only the gaps, one line
  each: `testDir` doesn't cover the scenarios directory; no `grepInvert`
  for the external tag; no `webServer` (the replay can't start the app on
  its own); `reuseExistingServer` off.

## CI template — printed, never written

Only when at least one layer above was accepted, ask once whether to print
a CI job template. Yes → print it in the report: one job with three steps —
install, integration tests with the local services started, end-to-end
tests without the external tag. Its first line says the project owns this
file. **Never write it**: not to `.github/workflows/`, not anywhere else.
