# Recording rules — what a saved scenario must satisfy before it is kept

Read from `SKILL.md` "Propose recording", step 2, every time a flow is
written to `<scenariosDir>`. The defects these rules close were found only
by running the scenarios, never by reading them, so the rules are checked
while writing the file and by running it, not left to code review.

## Rule 1. Find `alert` and `status` only inside a page region

Write `page.getByRole('main').getByRole('alert')` (or the form's own
region), never `page.getByRole('alert')`. Next.js renders a route
announcer (`#__next-route-announcer__`) with `role="alert"`; an unscoped
search finds two elements and strict mode fails. The same holds for
`status`, which announcers use too. Check before saving:
`grep -n "page.getByRole(\"alert\")\|page.getByRole('alert')" <file>` is empty.

## Rule 2. Wait for hydration before touching a form

Every scenario that fills or clicks inside a form calls
`waitForHydration(page)` after each `page.goto` and before the first form
action — no exceptions. The helper and the app-side marker it waits for:
`references/hydration-helper.md`. The first recording with a form writes
`<scenariosDir>/support/hydration.ts` from it and proposes the marker if the
app has none.

## Rule 3. A scenario that reaches a real external service is `@external`

`web-qa-manual-tester` reports, per flow, the hosts its requests went to
that are not `localhost`/`127.0.0.1` (`browser_network_requests`). A flow
is external when it *needs* one of them to pass — a sign-in against a
hosted auth service, a payment, a hosted API — not when a host only serves
analytics, fonts, images or other files the checked steps don't depend on.
Tagging every such flow would take it out of the replay before push for
nothing.

The human decides, in the recording question itself: name the hosts and
offer three answers — record as `@external` (left out of the replay before
push), record untagged (the hosts are incidental), or don't record. When a
host is the app's own backend (a hosted database the app uses in
development), add one line: scenarios that need it never run before push,
and pointing development at a local stack (`tests.integration`) would let
them.

## Rule 4. Three green runs before it is kept

```bash
npx playwright test <file> --repeat-each=3
```

Parallelism stays whatever the project's config says — the hydration race
showed up under parallel load, and running one at a time would hide it. One
red run → the file is not kept: fix it and run three again, or delete it.
Never leave a red file behind. An `@external` scenario runs once, not three
times: every run spends the external service's rate limit.

## Rule 5. Tag the scenario with its change

Every recorded scenario carries `@<change-slug>` (e.g. `@add-login`) — the
replay before push finds this change's scenarios by it. A later change that
edits an existing scenario adds its own tag next to the old one and never
removes the old one. Tags go in the `tag` option, together with
`@external`/`@local-stack` when they apply:

```ts
test('sign in with a wrong password', { tag: ['@add-login', '@external'] }, async ({ page }) => {
```

The `tag` option needs `@playwright/test` 1.42 or newer; on an older
version put the tags at the end of the title instead (`'sign in … @add-login'`).

## Rule 6. List the pages the scenario visits

The file's first line names the paths the flow actually opened, from
`web-qa-manual-tester`'s report for that flow — never a guess:

```ts
// pages: /sign-up, /auth/confirm, /dashboard
```

The replay before push uses this list to decide whether a change touched
the scenario. A scenario without it, or with an empty one, is always run.

## Suspense: a doubled form is an app defect

If strict mode finds two identical form elements while recording, the flow
FAILs and goes to `debug-loop` — it is usually a Suspense fallback that
renders the same form. Never "fix" the scenario with `.first()`, `.nth(0)`
or a looser locator: that hides a real defect behind a green test.
