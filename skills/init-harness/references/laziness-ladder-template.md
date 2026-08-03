# `.claude/docs/laziness-ladder.md` — what to reach for before writing new code

This ladder does not apply to trust-boundary validation, data-loss handling,
security, or accessibility. In these four areas "minimally sufficient" is the
wrong test — write the correct code directly and skip the ladder below.

Everywhere else, work down this list before writing anything new. Stop at the
first rung that solves the problem; reaching for rung 6 without checking 1-5
is exactly the premature abstraction Gate 4's Simplification check flags
after the fact — this ladder is the same judgement, applied before the code
is written instead of after.

1. **Do we need this at all?** (YAGNI) — a real requirement, not a guess
   about future need.
2. **Standard library / framework** — does the language or framework already
   do this?
3. **Native platform feature** — browser API, Node built-in, CSS — before
   reaching for a library.
4. **Already-installed dependency** — something already in the lockfile does
   this; don't add a second package for the same job.
5. **One line** — solvable inline, without a new function or file?
6. **Minimal custom code** — only once 1-5 are exhausted, write the smallest
   implementation that satisfies the requirement.
