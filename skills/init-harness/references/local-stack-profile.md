# Local stack profile — integration tests and email flows against local services

Read this when `references/test-layers.md` found a local service and the
user accepted the integration layer, when `web-qa` records a flow that sends
an email, and when `web-qa-manual-tester` walks one. Supabase CLI is the one
worked example; other stacks follow the same three commands, but this
version writes no template for them.

Every template below takes addresses and keys from the stack's own output.
None of them, and nothing in this plugin, reads the project's `.env*` files —
except the environment check in section 3, which runs the project's own
loader on the human's machine, never the agent's `Read`.

## 1. What a profile is

Three things the project declares in `tests.integration`
(`references/manifest-schema.md`):

| | Supabase CLI |
| --- | --- |
| `requires` — start it (shown to the human, never run) | `supabase start` |
| `healthCheck` — exits 0 when up | `supabase status` |
| where addresses and keys come from | `supabase status -o json` |

`-o json` rather than `-o env`: the JSON keys (`API_URL`, `DB_URL`,
`ANON_KEY`, `PUBLISHABLE_KEY`, …) are the ones the CLI's own tests assert
on; the `-o env` names are not documented as stably. Read the JSON with
`JSON.parse`, not with a shell `eval`.

## 2. Integration test config (Vitest)

Written only on the user's "yes" in Step 1b, next to the main config.

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

export default function setup(project: TestProject) {
  try {
    execSync('supabase status', { stdio: 'ignore' })
  } catch {
    throw new Error('Local services are not running — start them with: supabase start')
  }
  const status = JSON.parse(execSync('supabase status -o json', { encoding: 'utf8' }))
  const host = new URL(status.API_URL).hostname
  if (host !== 'localhost' && host !== '127.0.0.1') {
    throw new Error(`Integration tests run only against a local stack, got ${host}`)
  }
  project.provide('supabaseUrl', status.API_URL)
  project.provide('supabaseKey', status.PUBLISHABLE_KEY ?? status.ANON_KEY)
}

declare module 'vitest' {
  export interface ProvidedContext {
    supabaseUrl: string
    supabaseKey: string
  }
}
```

A test reads them with `inject('supabaseUrl')` from `vitest`. Global setup
runs in another process than the tests, so `provide`/`inject` is the way
across — setting `process.env` there does not reach them. Never the app's
`process.env`: the test checks code against the real service, and must not
change with whatever the developer's machine is configured for.

## 3. Environment check (`tests.e2e.preflight`)

The opposite job to section 2: talk to the service *the way the app is
configured to*, and check the answer has the expected shape. It is what
catches a wrong service address in the app's settings — the thing
integration tests deliberately can't see. A package script, e.g.
`"qa:preflight": "node scripts/qa-preflight.mjs"`; `init-harness` never
writes the `preflight` key itself (`references/test-layers.md`).

```js
// scripts/qa-preflight.mjs — Next.js + Supabase
import { loadEnvConfig } from '@next/env'
import { createClient } from '@supabase/supabase-js'

loadEnvConfig(process.cwd(), true) // the same loading next dev does
// Use the variable names the app's own client reads:
const url = process.env.NEXT_PUBLIC_SUPABASE_URL
const key = process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY ?? process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY
if (!url || !key) {
  console.error('preflight: the app has no Supabase address or key configured')
  process.exit(1)
}
const { error } = await createClient(url, key).auth.signInWithPassword({
  email: 'preflight@example.test',
  password: 'not-the-password',
})
if (error?.code !== 'invalid_credentials') {
  console.error(`preflight: expected invalid_credentials from ${url}, got ${error?.status ?? 'success'} ${error?.code ?? ''}`)
  process.exit(1)
}
console.log('preflight: ok')
```

A wrong address answers 404 or doesn't answer — either way not
`invalid_credentials`, and the check stops before any browser pass.

## 4. Email flow scenario (Playwright, Mailpit)

Current Supabase CLI ships **Mailpit** as its mail catcher (port 54324 by
default; the `[inbucket]` config section is now `[local_smtp]`). Older CLI
versions shipped Inbucket, with a different HTTP API. To tell: open the
mail UI from `supabase status` — the row is labelled Mailpit or Inbucket.
This template supports Mailpit only.

```ts
// <scenariosDir>/sign-up-confirm.spec.ts
import { test, expect, type APIRequestContext } from '@playwright/test'
import { execSync } from 'node:child_process'

function mailCatcherUrl(): string {
  const status = JSON.parse(execSync('supabase status -o json', { encoding: 'utf8' }))
  // The key name for the mail UI varies by CLI version; check `supabase status -o json` once.
  return status.MAILPIT_URL ?? status.INBUCKET_URL ?? 'http://127.0.0.1:54324'
}

async function confirmationLink(request: APIRequestContext, to: string, timeoutMs = 30_000) {
  const mail = mailCatcherUrl()
  const deadline = Date.now() + timeoutMs
  while (Date.now() < deadline) {
    const found = await (await request.get(`${mail}/api/v1/search`, { params: { query: `to:${to}` } })).json()
    if (found.messages?.length) {
      const message = await (await request.get(`${mail}/api/v1/message/${found.messages[0].ID}`)).json()
      // The default template links to /auth/v1/verify; adjust to the project's own email template.
      const link = message.Text.match(/https?:\/\/\S*\/auth\/v1\/verify\S*/)?.[0]
      if (link) return link
    }
    await new Promise((resolve) => setTimeout(resolve, 250))
  }
  throw new Error(`no confirmation email for ${to} within ${timeoutMs} ms`)
}

test('sign up, confirm by email, signed in', { tag: '@local-stack' }, async ({ page, request }) => {
  const email = `e2e-${Date.now()}@example.test` // a fresh user every run
  await page.goto('/sign-up')
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill('Correct-horse-42')
  await page.getByRole('button', { name: 'Sign up' }).click()
  await page.goto(await confirmationLink(request, email))
  await expect(page.getByRole('banner')).toContainText(email)
})
```

Three things the template must keep: a unique email per run (a rerun
otherwise fails on "user already exists"); polling with a deadline, never a
fixed wait; the mail catcher's address from the stack's own output. Labels,
routes and the signed-in check are the project's own — the ones above are
placeholders to replace with what the recorded flow actually used.

## 5. Tags: `@local-stack`, not `@external`

An email-flow scenario only talks to the local stack, so it is **not**
`@external` and belongs in the replay before push. It does need the stack
up, so it is tagged `@local-stack`. The Playwright config is not changed
for this: the replay adds `--grep-invert @local-stack` on the command line
when `tests.integration.healthCheck` is missing or fails, and reports how
many scenarios it left out with the reason `local services down`. The
config's own `grepInvert` for `@external` still applies — since Playwright
1.27 the config and the command line filters are applied together.

## Who reads this file

- `init-harness` (`references/test-layers.md`) — section 2 on a "yes" to
  the integration layer, section 1 for `requires`/`healthCheck`.
- `web-qa` — section 4 when recording a flow that sends an email, section 5
  for its tag.
- `web-qa-manual-tester` — when walking a flow that sends an email, it opens
  the mail catcher's web UI itself, given the address by `web-qa`, instead
  of asking the human for the link. No local stack → it asks, as before.
