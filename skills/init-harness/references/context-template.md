# `CONTEXT.md` — the project's glossary

A flat file at the target repo's root, one section: `## Glossary`. It exists
so every document and every review agent in this harness reads the same
meaning for the same domain word instead of drifting apart silently — two
proposals can each be internally consistent, each pass spec review, and
still disagree about what "user" means, and nothing catches that until a
person notices the tests check different things.

This is a different file from `openspec/config.yaml`'s `context:` block
(`references/openspec-config-seed.md`): that block is three to five lines
describing what the project *is*, read once per artifact generation.
`CONTEXT.md` is a growing list of *terms*, read by `spec-reviewer` on every
run.

## What belongs in the glossary, and what doesn't

Domain terms only — words specific to this project's problem space, the
kind two people could reasonably disagree about. Generic technical
vocabulary (request, cache, queue, session) does not belong here: if a term
is explained in any textbook, this file is not its home.

## Format

One line per term, two parts, both required:

```
<term> — <one-sentence definition>. Not to be confused with <similar term>,
because <what actually differs>.
```

The second part is not optional. A definition without it doesn't help: a
term is usually disputed because of a neighboring term, not in isolation —
naming the neighbor is what actually prevents the drift this file exists to
stop.

## Creation rule

Created empty, with the heading and one example line, at `init-harness` Step
5 — same never-overwrite rule as the other files that step writes
(`references/git-conventions-template.md`,
`references/laziness-ladder-template.md`, `PROGRESS.md`): write it only when
it doesn't already exist, never touch it on a re-run. It fills in gradually
as terms actually come up in specs, not all at once at setup time.

## Template

```markdown
# Context

## Glossary

- <term> — <one-sentence definition>. Not to be confused with <similar
  term>, because <what actually differs>.
```
