# Local stack profile — integration tests and email flows against local services

Read this when `references/test-layers.md` found a local service and the
user accepted the integration layer, when `web-qa` records a flow that sends
an email, and when `web-qa-manual-tester` walks one.

This plugin knows no specific stack. Everything it needs is what the project
declares in `tests.integration` (section 1); the templates below are filled
from those fields when written, and no instruction here runs a stack's own
command by name. `references/test-layers.md` holds the sign table that
proposes values for known stacks.

Every template takes addresses and keys from the stack's own output. None of
them, and nothing in this plugin, reads the project's `.env*` files — except
the environment check in section 3, which runs the project's own loader on
the human's machine, never the agent's `Read`.

## 1. What a profile is

Four fields in `tests.integration` (`references/manifest-schema.md`):

| Field | What it is | Who uses it |
| --- | --- | --- |
| `requires` | how a human starts the stack | messages only; never run |
| `healthCheck` | exits 0 when the stack is up | `.husky/pre-push`, the templates, `web-qa`, the replay |
| `envCommand` | prints one JSON object of addresses and keys | the integration test template |
| `mailCatcherUrl` | the stack's Mailpit address, optional | the email-flow template, `web-qa` |

No `envCommand` → section 2's template is not offered; no `mailCatcherUrl`
→ section 4's is not, and `web-qa-manual-tester` asks the human for an
email's link as before.

## 2. Integration test config (Vitest)

Written only on the user's "yes" in Step 1b, next to the main config, with
`<healthCheck>`, `<requires>` and `<envCommand>` replaced by those
`tests.integration` fields — the template never reads `.claude/harness.json` at run time.

```ts
// vitest.integration.config.ts
import { defineConfig } from 'vitest/config'

export default defineConfig({
  test: {
    include: ['**/*.integration.test.ts'],
    globalSetup: ['./tests/integration/global-setup.ts'],
  },
})
```

```ts
// tests/integration/global-setup.ts
import { execSync } from 'node:child_process'
import type { TestProject } from 'vitest/node'

const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1'])

export default function setup(project: TestProject) {
  try {
    execSync('<healthCheck>', { stdio: 'ignore' })
  } catch {
    throw new Error('Local services are not running — start them with: <requires>')
  }
  const env: Record<string, string> = JSON.parse(execSync('<envCommand>', { encoding: 'utf8' }))
  for (const [name, value] of Object.entries(env)) {
    if (!/^[a-z][a-z0-9+.-]*:\/\//i.test(value)) continue
    const host = new URL(value).hostname
    if (!LOCAL_HOSTS.has(host)) {
      throw new Error(`Integration tests run only against a local stack, but ${name} points at ${host}`)
    }
  }
  project.provide('localStack', env)
}

declare module 'vitest' {
  export interface ProvidedContext {
    localStack: Record<string, string>
  }
}
```

A test reads `inject('localStack')` from `vitest` and picks the keys its
stack prints. Global setup runs in another process than the tests, so
`provide`/`inject` is the way across — setting `process.env` there does not
reach them. Never the app's `process.env`: the test checks code against
the real service, and must not change with whatever the developer's
machine is configured for. Every URL-shaped value is checked, so a stack
that prints a remote address stops the run instead of quietly reaching it.

## 3. Environment check (`tests.e2e.preflight`)

The opposite job to section 2: talk to a service *the way the app is
configured to*, and check the answer has the expected shape. It is what
catches a wrong service address in the app's settings — the thing
integration tests deliberately can't see. A package script, e.g.
`"qa:preflight": "node scripts/qa-preflight.mjs"`; `init-harness` never
writes the `preflight` key itself (`references/test-layers.md`).

```js
// scripts/qa-preflight.mjs — one probe per external service the app uses
import { loadEnvConfig } from '@next/env'

loadEnvConfig(process.cwd(), true) // the same loading next dev does

const probes = [
  // { name, url: <the app's own setting>, init: <a request that cannot change data>, expect: <status> }
]

let failed = false
for (const { name, url, init, expect } of probes) {
  if (!url) { console.error(`preflight: ${name} has no address configured`); failed = true; continue }
  const status = await fetch(url, init).then((r) => r.status, () => 'no answer')
  if (status !== expect) { console.error(`preflight: ${name} at ${url} answered ${status}, expected ${expect}`); failed = true }
}
if (failed) process.exit(1)
console.log('preflight: ok')
```

Pick a request whose answer differs between "right service, wrong input"
and "wrong address": a sign-in with a deliberately wrong password answers
400 from a real auth service and 404 or nothing from a wrong address —
which was exactly the failure this check exists for. Never a request that
writes data.

## 4. Email flow scenario (Playwright, Mailpit)

Offered only when `mailCatcherUrl` is set; `web-qa` replaces
`<mailCatcherUrl>` with it when writing the file. The template speaks
Mailpit's HTTP API (`GET /api/v1/search?query=to:<address>`, then
`GET /api/v1/message/<ID>` → `Text`). A stack whose mail catcher is
something else (older Supabase CLI versions shipped Inbucket) needs its own
two requests here; open the catcher's web UI to see which it is.

```ts
// <scenariosDir>/sign-up-confirm.spec.ts
import { test, expect, type APIRequestContext } from '@playwright/test'

const MAIL_CATCHER = '<mailCatcherUrl>'

async function emailLink(request: APIRequestContext, to: string, timeoutMs = 30_000) {
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const found = await (await request.get(`${MAIL_CATCHER}/api/v1/search`, { params: { query: `to:${to}` } })).json()
    if (found.messages?.length) {
      const message = await (await request.get(`${MAIL_CATCHER}/api/v1/message/${found.messages[0].ID}`)).json()
      // The first link in the email; narrow the pattern to the project's own template if it has several.
      const link = message.Text.match(/https?:\/\/\S+/)?.[0]
      if (link) return link
    }
    await new Promise((resolve) => setTimeout(resolve, 250))
  }
  throw new Error(`no email for ${to} within ${timeoutMs} ms`)
}

test('sign up, confirm by email, signed in', { tag: '@local-stack' }, async ({ page, request }) => {
  const email = `e2e-${Date.now()}@example.test` // a fresh user every run
  await page.goto('/sign-up')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill('Correct-horse-42')
  await page.getByRole('button', { name: 'Sign up' }).click()
  await page.goto(await emailLink(request, email))
  await expect(page.getByRole('banner')).toContainText(email)
})
```

Three things the template must keep: a unique email per run (a rerun
otherwise fails on "user already exists"); polling with a deadline, never a
fixed wait; the mail catcher's address from the manifest, never a guess.
Labels, routes and the signed-in check are the project's own — the ones
above are placeholders to replace with what the recorded flow actually used.

## 5. Tags: `@local-stack`, not `@external`

An email-flow scenario only talks to the local stack, so it is **not**
`@external` and belongs in the replay before push. It does need the stack
up, so it is tagged `@local-stack`. The Playwright config is not changed
for this: a replay adds `--grep-invert @local-stack` on the command line
when `tests.integration.healthCheck` is missing or fails, and reports how
many scenarios it left out with the reason `local services down`. The
config's own `grepInvert` for `@external` still applies — since Playwright
1.27 the config and the command line filters are applied together.

## Who reads this file

- `init-harness` (`references/test-layers.md`) — section 1 for the fields,
  section 2 on a "yes" to the integration layer.
- `web-qa` — section 4 when recording a flow that sends an email, section 5
  for its tag and for its own replay.
- `web-qa-manual-tester` — when walking a flow that sends an email, it opens
  `mailCatcherUrl`'s web UI itself, given the address by `web-qa`, instead
  of asking the human for the link. No address → it asks, as before.
