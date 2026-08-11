# context7 lookup — trigger, order of operations, and the mark

Read this from `opsx-apply-git` §3 step 2, in both cases, before writing any
code for a task, and from `code-review/SKILL.md` before delegating to
`code-reviewer`, when its own 0-token diff scan (below) fires. One trigger
list, one mark format, two readers — `harness-audit/v0.6.0-implemented/`
`04-design-rationale.txt` decision 10 explains why this lives in one file
instead of being split across two pointing at each other.

## The trigger

The task's own text or acceptance criteria (`opsx-apply-git`), or the diff
itself (`code-review`), names a specific library or a framework-specific
API — not a generic description of behavior ("fix the save button"). This
plugin currently develops only against React and Next.js
(`04-design-rationale.txt` decision 9 covers why the trigger stays this
narrow rather than firing on every task), so the list below is
representative of those two, not exhaustive:

```
next/navigation, next/router, next/image, next/font, next/headers,
"use server" / Server Actions, "use client", useTransition, useOptimistic,
useFormState, useActionState, generateMetadata, generateStaticParams,
revalidatePath, revalidateTag, middleware.ts, React Suspense, the use()
hook
```

For `opsx-apply-git`, recognizing the trigger is a plain reading of text
already being read to implement the task — no separate mechanism needed.
For `code-review`'s diff-based check, match with the same 0-token shell
approach the risk and traceability prefilters already use
(`skills/code-review/references/deep-review.md`,
`traceability-prefilter.md`):

```bash
range="<parent>..HEAD"
lib_re='next/navigation|next/router|next/image|next/font|next/headers|useTransition|useOptimistic|useFormState|useActionState|"use server"|"use client"|generateMetadata|generateStaticParams|revalidatePath|revalidateTag|middleware\.ts|Suspense|\buse\('
hits=$(git diff "$range" | grep '^+' | grep -v '^+++' | grep -oiE "$lib_re" | sort -u)
```

Empty `$hits` → no trigger, review continues without context7. Non-empty →
check the mark (below) before deciding whether to call it.

## Looking it up

Two MCP calls, in order:
`mcp__plugin_sdd-harness-web-ykryshtopa_context7__resolve-library-id` with
the matched name, to get its context7-compatible ID; then
`mcp__plugin_sdd-harness-web-ykryshtopa_context7__query-docs` with that ID
and the matched API/topic, read before writing (or, at review time, before
judging) the code that uses it.

Those are the plugin's own server, pinned to `@upstash/context7-mcp@4.0.0`
in `mcp-config.json`. The bare `mcp__context7__*` spelling is a *different*
server — one the user or the project configured, commonly at `@latest` — and
naming it here would quietly undo the pin, the same way the bare Playwright
names once did in `agents/web-qa-manual-tester.md`. If only the bare pair
resolves, this plugin's server is disabled: say so in the output and
continue without the lookup, exactly as for any other context7 failure.

## The mark

One line in the group's own commit message, one per distinct name looked
up: `context7: <name> checked` (e.g. `context7: next/navigation checked`).
More than one in the same group → comma-separate them on one line:
`context7: next/navigation, useTransition checked`.

## code-review reads the mark before asking again

Before calling context7 itself, `code-review` checks whether this run's own
commits already carry the mark for the matched name(s):

```bash
range="<parent>..HEAD"   # the same range the trigger scan above resolves
already=$(git log "$range" --format=%B | grep -oE 'context7: .*checked' || true)
```

Matched name already listed there → do not call context7 again for it; tell
`code-reviewer` the lookup already happened at generation time. Matched name
not listed (or no mark at all) → call context7 now, and pass the result to
`code-reviewer` as context, the same way `framework` and `disabledRules`
already are.

## When it's unavailable

Network unreachable, rate limit hit, or any other MCP error, at either
point, never stops the run or the review. At generation, implement the task
from the model's own knowledge and say so plainly in the report — name what
failed and why. At review, review the diff without the context7 result and
say so plainly in `code-reviewer`'s output — name what failed and why.
Silent skip is not allowed at either point.
