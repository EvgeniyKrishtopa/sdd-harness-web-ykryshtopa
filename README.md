# sdd-harness-web-ykryshtopa

A Claude Code plugin that puts a spec-driven review harness around a
**Vite or Next.js** project (yarn/npm/pnpm, Vitest/Jest). It detects your
stack instead of assuming one.

What you get:

- every change starts as an OpenSpec proposal, swept for ambiguity, reviewed,
  and given a test plan before any code is written;
- code is written in task groups, one branch and one commit per group, one
  PR per run, each PR carrying its own review trail;
- automated reviews — architecture, spec, real-browser QA, code and test
  coverage, the harness itself — plus a security review that runs only when
  a diff looks risky;
- git hooks and Claude Code hooks that guard commits and pushes even when no
  agent is involved.

---

## Requirements

- **Claude Code >= 2.1.220** — `/init-harness` stops below it, and every
  session start warns (`skills/init-harness/references/claude-code-version.md`).
- **Node >= 20.19.0** (OpenSpec needs it).
- **GitHub with `gh` installed and logged in.** On another forge every check
  still runs, but PRs are printed for you to open by hand.
- **OpenSpec with the `new`, `continue` and `verify` workflows.**
  `/init-harness` offers to switch them on. The setting lives in
  `~/.config/openspec/config.json` — per machine, so each teammate and each
  CI runner sets it once.

Two MCP servers ship with the plugin and start on their own: Playwright (for
browser QA) and context7 (library docs). No API key needed.

---

## Install and update

```
/plugin marketplace add EvgeniyKrishtopa/sdd-harness-web-ykryshtopa
/plugin install sdd-harness-web-ykryshtopa@sdd-harness-web-ykryshtopa
```

Restart Claude Code (or `/reload-plugins`), then run `/init-harness` in each
repository. Installing writes nothing into your project; `/init-harness`
does.

**Updating is always two steps:**

```
/plugin update sdd-harness-web-ykryshtopa
/init-harness            # in every configured repository
```

The plugin update refreshes skills, agents and hooks only. `/init-harness`
sees that the repository is behind (`harnessVersion` in
`.claude/harness.json`) and runs in upgrade mode: it adds only what's
missing, shows a diff before touching a file you may have edited, and
leaves everything else alone. What it does on each version is listed in
`CHANGELOG.md` under **Upgrade**. Upgrading to 0.12.0, for example, asks
you to confirm one commit on `main` that takes `PROGRESS.md` out of git;
your copy of the file is kept.

To stay on one release, point your marketplace entry at its tag:
`"ref": "sdd-harness-web-ykryshtopa--v0.12.0"`.

---

## What `/init-harness` sets up

- OpenSpec, with `openspec/config.yaml` seeded from your project.
- `.claude/harness.json` — the one settings file every skill and hook reads
  (see [Settings](#settings)).
- `.claude/docs/` — git conventions (including when the agent may commit on
  its own), review policy, and a pointer block in `CLAUDE.md`/`AGENTS.md`
  so they are actually read.
- `CONTEXT.md` (glossary) and `PROGRESS.md` (where you left off). `PROGRESS.md`
  is local to your machine and gitignored.
- Git hooks via Husky: `pre-commit` runs typecheck, lint and `lint-staged`; `pre-push` runs
  tests with coverage, integration tests if you have them, then a dependency
  audit — either the package manager's own command or
  `scripts/deps-audit.mjs` with an allowlist of known advisories, each with
  an expiry date. You choose once.
- `permissions` in `.claude/settings.json` (secrets, destructive commands
  and package installs are denied) and `.claudeignore`.
- Optional test layers, offered only when it finds the sign for them (see
  [Test layers](#test-layers)).

It runs your typecheck, lint and coverage for real and marks the repository
configured only when all three pass. It also tells you which lint rule sets
you're missing (`react-hooks`, `jsx-a11y`, `@typescript-eslint`,
`@next/next`) — a recommendation only.

---

## Everyday workflow

**1. `/opsx-propose-review`** — propose a change. It sizes the change
(`short` or `full` route), drafts the artifacts, then runs the architecture
review, the ambiguity sweep (full route), the spec review and the test plan.
You end with every ambiguity resolved or deferred with an owner, and every
acceptance criterion mapped to a planned test.

**2. `/opsx-scaffold`** — only for a change that adds a module or a new
boundary (and `scaffold.enabled`). It turns the approved design into typed
stub files, confirms the file map with you, and has it reviewed.

**3. `/opsx-apply-git`** — implement the next run: either a batch of
`isolated` groups on its own, or one `judgement-heavy` group with you in the
loop. Each group gets its own branch and commit. Before writing code against
a library API it checks the docs through context7. Decisions worth keeping
are written to `docs/decisions/`.

Before cutting a group branch it checks the parent branch:

- a leftover group branch whose PR has merged → it switches to that PR's
  base on its own;
- a parent already behind `main` → it asks: send PRs into `main`, catch the
  parent up to `main` (fast-forward), or keep it. The answer is remembered.

**4. Reviews before push** — once per run, not per group: browser QA
(`web-qa`, if the UI changed), then code review with test coverage, then
the harness review. The security review joins only when a free check finds
risk signals (auth, payments, migrations, secrets, CI files…); documents and
tests alone don't trigger it. In a run with you in the loop, each doubtful
finding comes to you as its own question: Fix, or Keep as is. A browser QA
failure or a confirmed finding you want fixed goes through `debug-loop`,
which stops after `maxFixAttempts` and hands it to you.

If the push fails only on the dependency audit and the run didn't touch
`package.json` or the lockfile, it says so and suggests fixing it on a
separate branch off `main`.

**5. You merge the PR.** Its body has *What changed and why* and a
*Review trail*: every check's verdict or skip reason, confirmed findings,
deferred questions. The harness log (`.claude/harness-log/`) is committed
with it.

**6. On the last group** the change is archived through its own PR.

**Small tasks outside OpenSpec** — a dependency bump, a config tweak, a
one-file fix: ask `opsx-apply-git` for a chore run. Branch `chore/<slug>`
off `main`, the same checks, the same PR. Installing a package stays your
step: the agent stops and prints the exact command (`! npm install
zod@4.1.0`).

---

## What runs on its own

| When | What |
| --- | --- |
| every session start | git status, recent commits, `PROGRESS.md`'s status and next steps |
| `git commit` | `pre-commit`: typecheck + lint. The plugin's guard asks before a commit on `main`, a secret-shaped or very large diff, or one that skips hooks |
| `git push` | `pre-push`: tests with coverage → integration tests → dependency audit. The guard asks before a force-push or a push that skips hooks |
| end of a turn | typecheck, so the session doesn't stop on broken types |
| reading files | `.claudeignore` is enforced |

`permissions.deny` is what actually blocks secrets and dangerous commands;
`.claudeignore` only keeps noise (build output, lockfiles) out of reads.

### Test layers

Integration and end-to-end tests are optional. `init-harness` offers each
one when it sees a local service or `@playwright/test`, and writes the
`tests` block of `.claude/harness.json` on your yes.

- **Integration tests** run in `pre-push`, against local services only;
  their addresses come from `tests.integration.envCommand`, never from
  `.env*`.
- **Recorded browser scenarios** replay before each push of a run
  (`tests.e2e.replayBeforePush`): this change's scenarios, and on the last
  run also the older ones whose pages the change touched.
- **An environment check** runs first, so a stopped service is reported as
  an environment problem, not chased in the code.

The plugin never writes CI files; at most it prints a job template.

---

## Settings

`.claude/harness.json` — the fields you're most likely to change:

- **`models.*`** — which model each review uses: `opus`, `sonnet`, `haiku`
  or `fable`. Each name follows the newest model of its family, so you never
  edit versions. To pin a specific version, set
  `ANTHROPIC_DEFAULT_OPUS_MODEL` (or `_SONNET_`, `_HAIKU_`, `_FABLE_`) in the
  `env` block of `.claude/settings.json`.
- **`disabledRules`** — switch off single review rules by code (`CR-07`,
  `SR-02`, `DR-03`). Every finding names its rule.
- **`maxFixAttempts`** — how many tries `debug-loop` gets before asking you
  (default 2).
- **`trivialDiffThreshold` / `trivialDiffPaths`** — tiny diffs in these paths
  skip the code review.
- **`makerChecker.enabled`** — a separate agent writes each group's tests
  before the code exists, and the code may not edit them. Off by default.
- **`scaffold.enabled`**, **`designSystem.enabled`** — the stub-file step and
  the design-system record with per-change UI plans.
- **`depsAudit`** — `"plain"` or `"script"`, set by the question in
  `init-harness`.

Full schema: `skills/init-harness/references/manifest-schema.md`.

---

## Skills and agents

| Skill | What it does |
| --- | --- |
| `init-harness` | Set up a repository; re-run after every plugin update |
| `opsx-propose-review` | Propose a change with all its reviews and the test plan |
| `opsx-update-review` | Revise a change's plan and re-run what the revision touched |
| `opsx-scaffold` | Turn the approved design into stub files |
| `opsx-apply-git` | Implement the next run, open its PR, archive at the end; chore runs |
| `architecture-review` | Boundaries and coupling in `design.md`, against past decisions |
| `spec-clarify` | Find wording two engineers would read two ways |
| `spec-review` | Consistency, the readiness checklist, isolated vs judgement-heavy groups |
| `test-plan` | One row per acceptance criterion: which test closes it, at which level |
| `ui-plan`, `design-system` | Screens, states and components to reuse, before UI code (opt-in) |
| `web-qa` | Real-browser QA through Playwright |
| `code-review` | Correctness, simplification and test coverage; the security review when risky |
| `harness-review` | Drift in the harness setup itself; `harness-stats` reads the log |
| `debug-loop` | Bounded fix loop that hands over to you |
| `record-decision` | Record a decision made outside the flow |
| `dead-code-report` | Unused files, exports and dependencies, sorted by confidence; deletes nothing |

The skills call eight agents (`agents/`). Six can't write at all;
`spec-reviewer` only adds the isolated/judgement-heavy marker to
`tasks.md`, and `test-author` writes only tests, and only with
`makerChecker` on. The two
reviewers of code look up library behaviour in context7 themselves and mark
a claim they couldn't confirm.

**Name clash:** a bare `/code-review` runs Claude Code's built-in. Use
`/sdd-harness-web-ykryshtopa:code-review`, or just `/opsx-apply-git`. The
hyphenated `opsx-*` skills are this plugin's, not OpenSpec's `/opsx:*`.

**MCP servers:** Playwright (pinned `@playwright/mcp@0.0.78`, with cookie
tools to test an expired login) and context7. If you run your own copies too,
both keep working side by side. In a session that won't run `web-qa`,
disable Playwright via `/mcp`.

---

## Design principle

**AI review is a sensor, not a verdict — the human owns the merge.** Reviews
stop the run only on a confirmed finding; doubtful ones never block on their
own. Browser QA and the harness review are must-pass. Every reviewer also
says how confident it is in the review as a whole (`reviewConfidence`).

---

## Working on the plugin

**Structure.** A `SKILL.md` keeps the control flow and loads in full every
time; detail lives in `references/` and loads only when a step needs it.
`tests/smoke-json-schema.sh` checks that every reference is reachable,
every named path exists, and each `SKILL.md` and agent stays under its line
cap.

### Versioning and releases

The version lives only in `.claude-plugin/plugin.json`, and an
install sees a change only when it goes up.

1. Bump `version` in `.claude-plugin/plugin.json`.
2. Add `## <version>` to `CHANGELOG.md`.
3. Run every test: `for t in tests/*.sh; do bash "$t" || break; done`.
4. After the release is merged into `main`: `claude plugin tag --push`.

### The eval set

`evals/` holds 26 routing cases — which skill must fire, which must stay
silent — and cases grown from real defects. It is run by hand with
`claude plugin eval`, which is in early access and enabled per
organization. Run it after editing a skill description, before
trying a cheaper model, and when a fixed defect becomes a case. Details in
`evals/README.md`.

### Harness diet

Once a month, skip one review or move it to a cheaper
model for a while, and compare `harness-stats` before and after. No real
difference → trim it for good and record the decision. A cheaper model
first has to pass the eval set.
