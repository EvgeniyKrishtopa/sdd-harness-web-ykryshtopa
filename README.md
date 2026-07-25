# sdd-harness-web-ykryshtopa

Spec-driven OpenSpec harness for web projects — **Vite or Next.js**, either
package manager (yarn/npm/pnpm), either test runner (Vitest/Jest). Six
automated review gates, a branch-per-group git workflow, and a scaffolder
that detects your stack instead of assuming one.

## What this is

A Claude Code plugin extracting a proven OpenSpec review harness (originally
built for a Vite + React 19 + Redux Toolkit project) into a portable,
framework-detecting form so it can be dropped into any Vite or Next.js repo.

## Install

```
/plugin install sdd-harness-web-ykryshtopa@<your-marketplace>
```

## First run

```
/init-harness
```

Detects your framework, package manager, and test runner; installs and
initializes OpenSpec; asks for your coverage threshold; writes
`.claude/docs/git-conventions.md` and `.claude/docs/review-gates.md`; merges
`hooks.json` and a full `permissions` allow/deny list into your
`.claude/settings.json`; writes `.claudeignore` plus its enforcement hook;
installs a native git pre-commit hook via Husky (`.husky/pre-commit`) that
runs typecheck + lint + test:coverage on every commit — independent of
Claude Code's own hooks, so it still blocks bad commits made without any
agent involved.

### Permissions and `.claudeignore` — what's actually enforced

- **`permissions.deny`** (in `.claude/settings.json`) is the real,
  un-bypassable block — secrets (`.env`), destructive commands (`rm -rf`),
  and all four package managers' install commands stay denied regardless of
  which one this repo uses. This is Claude Code's own officially-supported
  mechanism.
- **`.claudeignore`** is *not* a native Claude Code file — there's no
  built-in reader for it. This plugin makes it real by pairing it with a
  `PreToolUse` hook (in `hooks/hooks.json`) that reads it and denies matching
  `Read`/`Grep` calls. Treat it as a noise-reduction convenience layer
  (build output, coverage, lockfiles) — not where secrets protection lives.
  See `skills/init-harness/references/claudeignore-template.md` for the full
  reasoning.

## Everyday workflow

1. `/opsx-propose-review` — propose a change (runs Gates 1-2).
2. `/opsx-apply-git` — implement the next run: an autonomous batch of
   `isolated` groups to one PR, or one `judgement-heavy` group with you in
   the loop.
3. Gates 3-6 (`web-qa` → `code-review` → `test-coverage` → `harness-review`)
   run automatically before each group's commit, per
   `.claude/docs/review-gates.md`.
4. You merge each run's PR on GitHub; the next `opsx-apply-git` re-syncs
   from that merge.
5. On the last group, `opsx-apply-git` archives the change via its own PR.

## Components

| Skill | Gate | Purpose |
|---|---|---|
| `init-harness` | — | One-time scaffolder: detects stack, installs OpenSpec, writes docs/hooks |
| `opsx-propose-review` | 1-2 | Propose a change, run architecture + spec review |
| `opsx-apply-git` | 3-6 | Implement a run inside the branch-per-group workflow |
| `opsx-update-review` | 1-2 | Revise an existing change's plan |
| `architecture-review` | 1 | Boundary/coupling risk on `design.md` or a diff |
| `spec-review` | 2 | Artifact consistency + isolated/judgement-heavy classification |
| `web-qa` | 3 | Real-browser QA via Playwright MCP, must-pass with a fix loop |
| `code-review` | 4 | Correctness bugs + simplification |
| `test-coverage` | 5 | Coverage gaps against your configured threshold |
| `harness-review` | 6 | Drift/staleness in the harness config itself |

Six matching read-only subagents live in `agents/` and are invoked by the
skills above, not usually directly.

## MCP servers

- **playwright** (`@playwright/mcp`) — drives a real browser for Gate 3.
- **sequential-thinking** — structured, revisable reasoning, used by
  `architecture-review`, `spec-review`, and `opsx-propose-review` on
  non-trivial changes.

## Design principle

AI review is a sensor, not a final verdict — the human owns the merge.
Gates 1, 2, 4, 5 pause only on a CONFIRMED finding; PLAUSIBLE-only or clean
reviews never block. Gates 3 and 6 are must-pass/always-shown by design —
see `.claude/docs/review-gates.md` (written by `init-harness`) for the full
policy once installed in your repo.
