# Step 2f — seeding `openspec/config.yaml` with this project's context and rules

## Why this file matters

`openspec init` (2b) creates `openspec/config.yaml` with nothing but default
schema settings. It is OpenSpec's own extension point: whatever `context:`
and `rules:` it holds get mixed into every artifact OpenSpec generates —
`proposal.md`, `design.md`, `tasks.md`, the delta specs. Left at its
defaults, every change in this repo is drafted by an agent that knows
nothing about the project, and Gates 1 and 2 spend their budget reviewing
artifacts that were generated blind. Shaping the artifact before generation
is cheaper than catching its shape at review — the same argument the review
gates themselves rest on, except this hook is OpenSpec's, not ours.

## The rule before any edit

Read the file first. `openspec init` wrote it, so it exists; treat every key
already in it as the user's. In particular **leave `schema:` alone** — it
selects the artifact set OpenSpec generates and is not ours to change. Add
only what is missing, and when a key we want is already present with
different content, show the difference and ask rather than replacing.

## What to write

1. **`context:`** — a block scalar. Fill the technical half from what Step 1
   already detected: framework, package manager, test runner, build output
   directory, dev server URL, and the top-level source layout. Do not invent
   anything here; every line is a fact already in hand.
2. Then ask the user, **once**, for three to five lines on what the project
   actually is — its domain, who uses it, the nouns that matter. This is the
   half no detection can produce, and the half that most changes an
   artifact's usefulness. Ask once, plainly, and accept a short answer. If
   they decline or skip it, write the technical half alone and move on.
   Never write a guessed domain: an invented description is worse than none,
   because every future artifact inherits it and nobody re-reads a file that
   looks already filled in.
3. **`rules.proposal`** — two rules, and both are load-bearing:
   - Every requirement carries a stable identifier. Use `FR-<n>` for
     functional and `NFR-<n>` for non-functional requirements, unique within
     the change, and never renumbered once written. Without identifiers, "is
     every requirement implemented?" can only ever be answered by a model's
     impression of a document. With them, it is a `grep`. Later gates depend
     on this being true of every proposal.
   - Every acceptance criterion states, in three parts, the state it assumes,
     the action taken, and the observable result: Given/When/Then. Without a
     format, "is this criterion testable as written?" is a model's judgement
     call that can go either way on the same text; `spec-reviewer` and
     `code-reviewer`'s coverage check both depend on there being a specific
     outcome to point at.
4. **`rules.tasks`** — two rules: each task names the requirement identifier
   it implements, and verification is a task in the list rather than
   something left for a human to remember afterwards. The first makes the
   proposal-to-task link traceable in the same mechanical way; the second is
   why a group can be considered done at all.

## Keep it to this

It is tempting to specify a full house style for `proposal.md` — sections,
ordering, headings — and a project that wants one should add it. A portable
plugin should not: a structure grown around one product's design system and
information architecture is exactly the kind of thing that fits its author
and nobody else. The rules above are the minimum the gates actually need to
function.

## The resulting shape

The values are this project's, not these:

```yaml
schema: spec-driven          # written by `openspec init`; left untouched

context: |
  Vite + React + TypeScript app; yarn; Vitest for tests; builds to dist/;
  dev server on http://localhost:5173. Source under src/, routes in
  src/routes/.
  Reviewed by the sdd-harness-web-ykryshtopa harness — see
  .claude/docs/review-gates.md for the gates and their order.
  <the user's three to five lines about the domain, or nothing at all>

rules:
  proposal:
    - Give every requirement a stable identifier — FR-1, FR-2 for functional
      requirements, NFR-1, NFR-2 for non-functional ones. Unique within the
      change. Never renumber an identifier once it is written.
    - State every acceptance criterion as Given/When/Then — the state it
      assumes, the action taken, the observable result.
  tasks:
    - Every task states the requirement identifier it implements.
    - Verification belongs in the task list as its own task, not left as a
      manual check after the fact.
```

Record nothing about this file in `.claude/harness.json` — `openspec/
config.yaml` is OpenSpec's, and a second copy of its contents in our manifest
would be one more pair of things to drift apart. Gate 6 reads the file
itself.
