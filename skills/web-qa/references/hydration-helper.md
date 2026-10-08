# Hydration helper — wait for the app, not for the network

Read from `references/recording-rules.md` rule 2, the first time a scenario
with a form is recorded in a project.

## Why a helper at all

A click on "submit" before React hydrates the page lands on the server
HTML: a form whose `action` is a client function carries React's
placeholder `action="javascript:throw new Error('React form unexpectedly
submitted.')"`, and a form with an `onSubmit` handler does a native submit
and reloads the page. Under parallel load this happens on some runs and not
others — the flakiest kind of failure a recorded scenario can have.

## What the helper waits for: a marker the app sets

The app sets one attribute on `<body>` from a client effect; the helper
waits for it. Nothing else is reliable:

- `waitForLoadState('networkidle')` — Playwright's own documentation marks
  it DISCOURAGED for testing.
- "the form has no `javascript:` action" — React leaves that placeholder in
  place **after** hydration too, so the wait never ends for a client-action
  form; a form with `onSubmit` never has it, so the wait ends at once,
  before hydration.

Measured on a built Next.js 16.4 + React 19 app, Playwright 1.64, 4
workers, 5 runs each, JS chunks delayed by 1.5 s: the marker passed 15 of 15
across a client-action form, a `useActionState` server-action form and an
`onSubmit` form. Without any wait the `onSubmit` form failed 5 of 5; the
`javascript:` check timed out 5 of 5 on the client-action form.

## In the app — proposed, never written unasked

If the app has no marker yet, show this diff and write it only on "yes".
Without it, no scenario with a form is recorded (rule 2 has no exceptions):
say so and record only the flows without one.

```tsx
// app/hydration-marker.tsx (Next.js App Router; in a Vite app, the same effect in the root component)
'use client'
import { useEffect } from 'react'

export default function HydrationMarker() {
  useEffect(() => {
    document.body.dataset.hydrated = 'true'
  }, [])
  return null
}
```

Rendered once, inside `<body>` of the root layout: `<HydrationMarker />`.
It sets the attribute on the first hydration of a document; a client-side
navigation keeps the same `<body>`, and a full reload starts over.

## In the scenarios directory

Written by `web-qa` once, at `<scenariosDir>/support/hydration.ts`:

```ts
import type { Page } from '@playwright/test'

/** Call after every page.goto / full navigation, before the first fill or click on a form. */
export async function waitForHydration(page: Page): Promise<void> {
  await page.locator('body[data-hydrated="true"]').waitFor({ state: 'attached' })
}
```

```ts
import { waitForHydration } from './support/hydration'

await page.goto('/sign-in')
await waitForHydration(page)
await page.getByLabel('Email').fill(email)
```
