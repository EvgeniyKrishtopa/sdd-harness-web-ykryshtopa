# sdd-harness-web-ykryshtopa

Spec-driven OpenSpec harness for web projects — **Vite or Next.js**, either
package manager (yarn/npm/pnpm), either test runner (Vitest/Jest). Six
automated review gates (five agent delegations — Gate 4 and Gate 5 share
one, see Components below), a branch-per-group git workflow, and a
scaffolder that detects your stack instead of assuming one.

## What this is

A Claude Code plugin extracting a proven OpenSpec review harness (originally
built for a Vite + React 19 + Redux Toolkit project) into a portable,
framework-detecting form so it can be dropped into any Vite or Next.js repo.

## Requirements

- **Node >= 20.19.0** — required by OpenSpec.
- **OpenSpec in Expanded (`custom`) profile, not the default Core profile.**
  This harness's gates are designed around OpenSpec's Expanded workflow set
  (`new`, `continue`, `verify`, ...), not the single-shot `propose` flow that
  Core ships with. `/init-harness` checks this and offers to switch it for
  you (see Step 2 of `skills/init-harness/SKILL.md`) — but be aware that
  **this setting lives in `~/.config/openspec/config.json`, a global,
  per-machine file, not anything committed to this repository.** That means:
  - it is **not** portable between machines or teammates — everyone who
    works on this repo needs to set it up on their own machine once;
  - CI runners won't have it unless you configure it there separately;
  - switching it affects every other OpenSpec project on that machine, not
    just this one.

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
`.claude/docs/git-conventions.md` and `.claude/docs/review-gates.md`; writes
`.claude/harness.json` — the single machine-readable manifest every other
skill and hook in this plugin reads instead of re-detecting your stack;
creates or appends a short pointer block in `CLAUDE.md`/`AGENTS.md` so that
those docs (and the auto-commit override they define) are actually
discoverable — Claude Code doesn't load `.claude/docs/*.md` into context on
its own the way it loads `CLAUDE.md`; merges a full `permissions` allow/deny
list into your `.claude/settings.json`; writes `.claudeignore` plus its
enforcement hook; installs native git hooks via Husky — `.husky/pre-commit`
(typecheck + lint + `lint-staged`, kept fast since it fires once per task
group) and `.husky/pre-push` (the full `test:coverage` run) — independent
of Claude Code's own hooks, so bad commits and pushes are still blocked
even with no agent involved.

This plugin's own Claude Code hooks (`hooks/hooks.json` — commit/merge/push
guards, `.claudeignore` enforcement, typecheck-before-stop, and a
`SessionStart` banner printing branch/status/recent commits) apply
automatically to any repo where the plugin is enabled, the same way its
skills and agents do. The commit/merge/push guards are plain shell — they
escalate to a confirmation prompt on a protected-branch commit, a
secret-shaped or unusually large staged diff, or a force-push, and stay out
of the way otherwise; no model call is involved. `/init-harness` does not copy them into your project's
`.claude/settings.json` — there is nothing to install for that layer.

### Permissions and `.claudeignore` — what's actually enforced

- **`permissions.deny`** (in `.claude/settings.json`) is Claude Code's own
  officially-supported enforcement mechanism, and it's the layer that blocks
  secrets (`.env`), destructive commands (`rm -rf` and its common variants),
  and every spelling of a dependency-adding command across npm, yarn, pnpm
  and bun — regardless of which one this repo uses. It is only as strong as `allow` is narrow, though: `allow`
  is checked first, and a broad `allow` entry (a bare `Write`, an unscoped
  `Bash(cat:*)` or `Bash(node -e:*)`) grants the call before `deny` ever gets
  a say, silently defeating any `deny` rule it overlaps with. This plugin's
  `allow` list is deliberately narrow — no generic file-write or arbitrary-code
  primitives — specifically so that `deny` isn't bypassable in practice, not
  because `deny` is inherently un-bypassable on its own.
- **`.claudeignore`** is *not* a native Claude Code file — there's no
  built-in reader for it. This plugin makes it real by pairing it with a
  `PreToolUse` hook (in `hooks/hooks.json`) that reads it and denies matching
  `Read`/`Grep`/`Glob` calls. Treat it as a noise-reduction convenience layer
  (build output, coverage, lockfiles) — not where secrets protection lives.
  See `skills/init-harness/references/claudeignore-template.md` for the full
  reasoning.

## Everyday workflow

1. `/opsx-propose-review` — propose a change (runs Gates 1-2).
2. `/opsx-apply-git` — implement the next run: an autonomous batch of
   `isolated` groups to one PR, or one `judgement-heavy` group with you in
   the loop.
3. Each group implements and commits as it goes; Gates 3-6 (`web-qa` →
   `code-review` [Gate 4 + Gate 5 in one delegation] → `harness-review`) run
   automatically once per run, after every group in it is already
   committed and before push — not once per group — per
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
| `code-review` | 4-5 | Correctness bugs + simplification, AND coverage gaps against your configured threshold — one delegation, two labeled sections |
| `harness-review` | 6 | Drift/staleness in the harness config itself |

Five matching subagents live in `agents/` and are invoked by the skills
above, not usually directly. Four are strictly read-only (`Read`/`Grep`/
`Glob` plus `Bash` scoped by their own prompts to inspection commands);
`spec-reviewer` additionally carries `Edit`, limited by its prompt to one
job — writing the `<!-- isolated -->` / `<!-- judgement-heavy -->` marker
onto a `tasks.md` heading, which is what `opsx-apply-git` reads to decide
what it may run unattended.

## Command names

- **`code-review` collides with Claude Code's own built-in `/code-review`
  slash command.** Inside the normal workflow this doesn't matter: `opsx-
  apply-git` runs Gate 4 itself via the `Agent` tool, not by invoking a
  slash command — and the built-in `/code-review` couldn't be invoked that
  way regardless, since it has `disable-model-invocation` (confirmed
  empirically; a plugin skill or agent cannot trigger it). It only matters
  if you want to run Gate 4 by hand outside that workflow: a bare
  `/code-review` always resolves to Claude Code's built-in command, never
  this plugin's skill. Use the namespaced form —
  `/sdd-harness-web-ykryshtopa:code-review` (substitute the marketplace
  alias you actually installed under, if different) — to reach this
  plugin's version directly, or just run `/opsx-apply-git`, which reaches
  it without the ambiguity.
- **This plugin's `opsx-propose-review` / `opsx-apply-git` /
  `opsx-update-review` skills are not the same thing as OpenSpec's own
  generated `/opsx:propose` / `/opsx:apply` / `/opsx:update` commands.**
  Once `init-harness` puts OpenSpec in Expanded (`custom`) profile with
  `delivery: "both"` (see Requirements above), both sets exist side by
  side — this plugin's are hyphenated (`opsx-apply-git`), OpenSpec's own
  are colon-namespaced (`opsx:apply`). Everything in this README's
  "Everyday workflow" and "Components" sections refers to this plugin's
  hyphenated skills, not OpenSpec's CLI-generated ones.

## MCP servers

- **playwright** (`@playwright/mcp`) — drives a real browser for Gate 3.
  Because it ships *inside* this plugin, Claude Code exposes its tools under
  the plugin-scoped names
  `mcp__plugin_sdd-harness-web-ykryshtopa_playwright__browser_*`, not the
  bare `mcp__playwright__browser_*` a project-level `.mcp.json` would
  produce — `web-qa-manual-tester`'s `tools:` list carries both spellings so
  the gate works whichever way Playwright MCP is provided.
  This is the only MCP server this plugin ships, and it stays resident for
  the whole session even though only Gate 3 ever calls it — there is no
  supported way, as of Claude Code 2.1.220, for a plugin's `.mcp.json` to
  load a server conditionally per-skill or per-gate; servers listed there
  attach for the session's lifetime once enabled. Two things narrow the
  actual cost, though: (1) Claude Code 2.1.x defers MCP tool schemas
  (`ToolSearch`) rather than loading all ~12 of Playwright's tools into
  context up front, so the static footprint is smaller than a naive count
  suggests; (2) `npx` resolves an already-cached/locally-installed package
  without a registry round-trip, so a project that installs
  `@playwright/mcp` as a devDependency (rather than relying on `npx -y` to
  fetch it fresh) avoids the network check on session start. Neither
  eliminates the server being resident for gates 1/2/4/5/6, which never
  touch a browser — if a session is known not to run `web-qa`, disable the
  server for it via `/mcp` (or remove/comment the entry from `.mcp.json` in
  a project fork) rather than leaving it attached by default.

This plugin previously also shipped a `sequential-thinking` MCP server for
`architecture-review` and `spec-review`'s non-trivial-change reasoning.
Removed: modern Claude models have native extended thinking that covers the
same step-by-step reasoning in one pass, without the added round-trip cost
of an external sequential-thinking tool call per "thought" (cost-optimization
#39).

## Design principle

AI review is a sensor, not a final verdict — the human owns the merge.
Gates 1, 2, 4, 5 pause only on a CONFIRMED finding; PLAUSIBLE-only or clean
reviews never block. Gates 3 and 6 are must-pass/always-shown by design —
see `.claude/docs/review-gates.md` (written by `init-harness`) for the full
policy once installed in your repo.
