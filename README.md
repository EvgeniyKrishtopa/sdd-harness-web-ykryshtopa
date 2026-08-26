# sdd-harness-web-ykryshtopa

A Claude Code plugin that wraps a spec-driven review harness around a
**Vite or Next.js** project — either package manager (yarn/npm/pnpm), either
test runner (Vitest/Jest). It extracts a harness proven on a Vite + React 19
+ Redux Toolkit project into a portable, stack-detecting form, so it can be
dropped into any Vite or Next.js repo.

What it puts around your work:

- **Seven automated review gates** (six agent delegations — Gates 4 and 5
  share one), plus a **security/architecture deep review** that spawns only
  when a 0-token prefilter flags the diff as risky.
- **An ambiguity sweep and a test plan** before implementation starts.
- **Architecture decision records** that the architecture gate reads back on
  every later change.
- **A branch-per-group git workflow**, with each PR carrying its own review
  trail.
- **A scaffolder** that detects your stack instead of assuming one.

---

## Requirements

- **Claude Code >= 2.1.220** — a hard floor, not a preference, and one the
  plugin now checks rather than only documents. The plugin format has no
  field for declaring a minimum host version (`requirements` in
  `plugin.json` validates as an unknown key Claude Code ignores at load
  time), so the check happens twice instead: `/init-harness` reads the
  running version before anything else and stops without writing a single
  file if it's below the floor, and the `SessionStart` hook re-checks it
  every session and prints a warning above the git banner — because setup
  runs once, while the version can change under a repo any day after that.
  Neither one can be read → setup says so in one line and continues; the
  banner stays quiet. Reasoning and procedure:
  `skills/init-harness/references/claude-code-version.md`. The harness
  relies on plugin-bundled MCP tool names
  (`mcp__plugin_<plugin>_<server>__<tool>`, without which Gate 3's agent
  resolves nothing), on file permission rules being honoured for
  `Edit(path)`/`Read(path)` — what the generated `permissions` block is
  written against (2.1.210+) — on a subagent with an unresolvable `tools:`
  list refusing to launch rather than running toolless (2.1.208+), and on
  `stop_hook_active` in the `Stop` hook. 2.1.220 is the version every gate,
  hook and manifest was verified against.
- **Node >= 20.19.0** — required by OpenSpec.
- **GitHub as the code forge, with `gh` installed and authenticated.**
  Delivery (`opsx-apply-git`) opens pull requests through `gh pr create`,
  and only that path is proven. `/init-harness` detects the forge from `git
  remote get-url origin` and records it; on anything else (GitLab,
  Bitbucket, Azure DevOps, or no `origin` at all) every gate still runs, but
  delivery prints the branch, the target branch and the PR body instead of
  opening the PR — you open it by hand.
- **Two MCP servers ship with the plugin** and start automatically —
  Playwright for Gate 3 and context7 for library docs. Nothing to install or
  configure; no API key needed. See [MCP servers](#mcp-servers).
- **OpenSpec configured with the `new`, `continue` and `verify` workflows.**
  The gates are designed around OpenSpec's Expanded workflow set, not the
  single-shot `propose` flow Core ships with. `profile: custom` on its own
  is *not* the requirement — a custom profile can be missing exactly those
  workflows, which is what a partial pass through OpenSpec's interactive
  picker leaves behind. `/init-harness` checks the `workflows` list and
  offers to switch it for you (Step 2 of `skills/init-harness/SKILL.md`),
  but note that **the setting lives in `~/.config/openspec/config.json`, a
  global per-machine file, not anything committed to your repository:**
  - it is **not** portable between machines or teammates — everyone working
    on the repo sets it up once on their own machine;
  - CI runners won't have it unless you configure it there separately;
  - switching it affects every other OpenSpec project on that machine.

---

## Install

This repository is both the plugin and a single-plugin marketplace, so
adding it and installing from it are two steps against the same name:

```
/plugin marketplace add EvgeniyKrishtopa/sdd-harness-web-ykryshtopa
/plugin install sdd-harness-web-ykryshtopa@sdd-harness-web-ykryshtopa
```

The same commands work from a shell (`claude plugin marketplace add ...`,
`claude plugin install ...`). The quickest check that it loaded is `claude
plugin details sdd-harness-web-ykryshtopa`: it should list 17 skills,
7 agents by name, 3 hook events and 2 MCP servers. To install from a local
checkout, pass the absolute path to `marketplace add`. There is no npm
package — Claude Code installs plugins from marketplaces, not from the npm
registry.

**Restart Claude Code (or `/reload-plugins`) after installing:** skills take
effect immediately, but hooks, agents and MCP servers only load on start.

Then run `/init-harness` in each repository. Installing the plugin adds the
skills and hooks; it writes nothing into your project.

### Updating, pinning, removing

```
/plugin update sdd-harness-web-ykryshtopa      # or: claude plugin update ...
/plugin uninstall sdd-harness-web-ykryshtopa   # marketplace remove <name> to
                                               # forget the marketplace too
```

An update only arrives when this plugin's declared `version` changes —
Claude Code caches by resolved version and skips a plugin whose version it
already has. A fix pushed without a version bump therefore reaches nobody;
see [Versioning and releases](#versioning-and-releases) for how that's
handled, and `CHANGELOG.md` for what each version changed.

To hold a specific release rather than tracking the default branch, point
your own marketplace entry at a tag or commit:

```json
{
  "name": "sdd-harness-web-ykryshtopa",
  "source": {
    "source": "github",
    "repo": "EvgeniyKrishtopa/sdd-harness-web-ykryshtopa",
    "ref": "sdd-harness-web-ykryshtopa--v0.6.0"
  }
}
```

### Keeping a configured repository in step

**`/plugin update` only refreshes the plugin** — its skills, agents and
hooks. It writes nothing into your repository. Every release that adds a
file or a manifest key therefore needs one more step in each repo, and it is
always the same one:

```
/init-harness
```

It compares `.claude/harness.json`'s `harnessVersion` against the installed
plugin's `version`. Absent or lower means an already-configured repo, so it
switches to **upgrade mode** instead of re-running the first-time
questionnaire: it fills in only what's missing — new files, new manifest
keys, new rules appended to an existing `openspec/config.yaml` list — and
never overwrites a file you may have customized without showing you the diff
first. On a repo already at the current version it says so and changes
nothing.

What upgrade mode owns lives in one place,
`skills/init-harness/references/upgrade-mode.md`, and every release that
teaches the scaffolder to write something new adds its row there in the same
commit. Gate 6 (`harness-review`) checks your repo against that same
inventory, so a repo that fell behind surfaces as a finding rather than as a
check quietly reporting "not applicable" forever.

---

## First run

```
/init-harness
```

It detects your framework, package manager and test runner, then:

- **installs and initializes OpenSpec** in Expanded profile, seeding
  `openspec/config.yaml` with your project's detected context and artifact
  rules, and asks for your coverage threshold;
- **writes the project docs** — `.claude/docs/git-conventions.md`,
  `review-gates.md`, `laziness-ladder.md` — plus `PROGRESS.md`,
  `CONTEXT.md`, and `.gitattributes` entries marking `PROGRESS.md` and
  `.claude/harness-log.jsonl` `merge=union`, so every task-group branch in
  the branch-per-group workflow can append to both without conflicting.
  `docs/decisions/` is *not* created here — it appears on demand, the first
  time a decision actually outlives its change;
- **writes `.claude/harness.json`**, the single machine-readable manifest
  every other skill and hook reads instead of re-detecting your stack: the
  detected stack, the coverage threshold, the forge, per-gate model
  overrides, `disabledRules`, `maxFixAttempts` (the `debug-loop` skill's
  fix-attempt cap before it escalates to you), and `makerChecker` (off by
  default — see step 3 of the workflow below);
- **proves the detected toolchain actually runs** — typecheck, lint and
  coverage are executed for real, not just detected. Only once all three
  genuinely pass does it write `harnessVersion` and `toolchainVerifiedAt`,
  the two keys that record a repo as fully configured for this plugin
  version;
- **wires up your integration tests if they live in their own command.**
  Projects whose integration tests need a database or a running server
  usually keep them behind a second `package.json` script, and nothing here
  used to run it: written, committed, never executed. When such a script is
  found it goes into the manifest as the optional `scripts.testIntegration`,
  and `.husky/pre-push` becomes coverage → integration → audit. It is run
  once during setup first: if it fails here — the database isn't on this
  machine, say — the key is left out and the hook stays two links long,
  because a push check that can't pass is worse than tests nothing runs.
  Most projects run their integration tests in the same command as the rest;
  those get no key, no second link, and no question about it;
- **reports which linter rule sets you're missing** (`react-hooks`,
  `jsx-a11y`, `@typescript-eslint`, plus `@next/next` on Next.js), naming
  what each one stops catching. A recommendation only: it installs nothing
  and edits no config. A non-ESLint project gets one explicit line saying
  the check was skipped and why;
- **adds a pointer block to `CLAUDE.md`/`AGENTS.md`** so `.claude/docs/*.md`
  — and the auto-commit override they define — are discoverable at all;
  Claude Code doesn't load those files into context the way it loads
  `CLAUDE.md`;
- **merges a `permissions` allow/deny list** into `.claude/settings.json`,
  and writes `.claudeignore` plus its enforcement hook;
- **installs native git hooks via Husky** — `.husky/pre-commit` (typecheck +
  lint + `lint-staged`, kept fast since it fires once per task group) and
  `.husky/pre-push` (full `test:coverage`, then a blocking dependency
  vulnerability audit). These are independent of Claude Code, so bad commits
  and pushes are blocked even with no agent involved.

The plugin's own Claude Code hooks (`hooks/hooks.json`) need no
installation — they apply to any repo where the plugin is enabled, the same
way its skills and agents do: commit/merge/push guards, `.claudeignore`
enforcement, typecheck-before-stop, and a `SessionStart` banner printing
branch, status and recent commits plus (once `PROGRESS.md` exists) its
`Status` and `Next steps`, so a new session's first read answers what `git
log` alone can't. That banner also carries the Claude Code version warning
described under [Requirements](#requirements) — above the git section, and
only when the running version is below the floor. The guards are plain shell, no model call: they prompt for
confirmation on a protected-branch commit, a secret-shaped or unusually
large staged diff, or a force-push, and stay out of the way otherwise.

### What's actually enforced: permissions vs `.claudeignore`

- **`permissions.deny`** (in `.claude/settings.json`) is Claude Code's own
  supported enforcement mechanism, and the layer that blocks secrets
  (`.env`), destructive commands (`rm -rf` and its variants), and every
  spelling of a dependency-adding command across npm, yarn, pnpm and bun.
  It is only as strong as `allow` is narrow: `allow` is checked first, so a
  broad entry (a bare `Write`, an unscoped `Bash(cat:*)` or
  `Bash(node -e:*)`) grants the call before `deny` gets a say. This plugin's
  `allow` list carries no generic file-write or arbitrary-code primitives,
  specifically so `deny` isn't bypassable in practice.
- **`.claudeignore`** is *not* a native Claude Code file — nothing reads it
  built-in. This plugin makes it real by pairing it with a `PreToolUse` hook
  that denies matching `Read`/`Grep`/`Glob` calls. Treat it as noise
  reduction (build output, coverage, lockfiles), not as where secrets
  protection lives — reasoning in
  `skills/init-harness/references/claudeignore-template.md`.

---

## Everyday workflow

**1. `/opsx-propose-review` — propose a change.** Before any artifact exists
it sizes the change from three observable questions (more than one module? a
data-schema change? a contract change?) and records `short` or `full` in
`openspec/changes/<change>/.route`. The same step records a second, separate
marker — `openspec/changes/<change>/.scaffold`, `yes` or `no` — from two more
observable questions (new module? a new boundary crossing?), but only when
the manifest has `scaffold.enabled: true`; otherwise it's written `no`
without asking. Then Gate 1; then — on the full route — `spec-clarify`,
which sweeps the drafted artifacts for wording two engineers would read two
ways and closes each finding with you one question at a time; then Gate 2;
then `test-plan`. You end up with a change whose ambiguities are resolved,
whose readiness is a printed five-condition checklist rather than a phrase,
and whose acceptance criteria each already have a planned test.

**2. `/opsx-scaffold` — turn the approved design into files, when the
change needs one.** Runs only when `.scaffold` says `yes`; every other
change skips straight to step 3. It never re-opens the architecture — that
was already settled in `design.md` and at Gate 1 — it only draws a file map
(path, responsibility, export) from those already-approved boundaries,
confirms the map with you in one question, then creates the files as typed
stub signatures with no bodies. Gate 2b (`architecture-reviewer`, in its
scaffold-review mode) checks the result against `design.md` before it's
committed on its own branch and merged. The scaffold map itself is written
into `design.md` as a new section, not a new file.

**3. `/opsx-apply-git` — implement the next run.** Either an autonomous
batch of `isolated` groups into one PR, or one `judgement-heavy` group with
you in the loop. Before writing code for a task that names a library or a
framework-specific API, it looks the API up through context7 and marks the
group's commit accordingly. A decision that crosses the recording threshold
(irreversible, multi-module, or had live alternatives) is written to
`docs/decisions/` from *either* branch — `Proposed` from an autonomous
group, `Accepted` when you were in the loop — and Gate 1 reads the accepted
ones back on every later change.

Optionally, the tests for a group come from a different actor than its
code. With `makerChecker.enabled` in the manifest, the `test-author` agent
writes the group's tests from the test plan before any of its code exists,
and the implementing session then writes code until they pass and may not
edit them — the test files are hashed before implementation and compared
before the commit, and a difference stops the group and asks you. The
failure this catches is the one the coverage gate cannot see: when the
author of the code misread the requirement, a test written by that same
author preserves the misreading and passes. Off by default; it costs one
extra subagent per group that has test-plan rows.

**4. Gates 3-6 run once per run**, after every group in it is committed and
before push — not once per group — per `.claude/docs/review-gates.md`:
`web-qa` → `code-review` (Gates 4 + 5 in one delegation) → `harness-review`.

- **Gate 3** checks every user-facing surface against a required UI States
  Matrix (loading/error/empty/offline, plus syncing/conflict where a project
  actually has background sync), taking the states from `design.md`'s
  sequence diagram for that flow when one exists — plus a required
  keyboard-only pass (reachability, focus visibility, tab order, modal
  focus-trap/Escape) that blocks the run on a FAIL just like any state does.
- **Gate 5** checks written tests against the change's own test plan,
  falling back to a grep over its `FR-`/`NFR-` identifiers when it has none;
  an uncovered ID surfaces by name before `code-reviewer` even runs.
- **Inside the same step**, a 0-token prefilter greps the diff for risk
  signals (auth, permissions, payments, migrations, config, secrets,
  uploads) and spawns `deep-reviewer` for a security and
  architecture-as-built pass only when one fires. Most runs skip it, and the
  skip is logged.
- **A `web-qa` FAIL or a CONFIRMED finding you choose to fix** runs through
  `debug-loop`: a bounded four-phase fix loop that escalates to you instead
  of retrying forever, records every hypothesis under `_debug/`, and
  classifies the fixed defect against the specification, so a missing
  acceptance criterion gets added rather than silently staying missing.

**5. You merge the run's PR.** Its body carries two sections: *What changed
and why* in plain prose, and a **Review trail** — a link to the change, one
line per gate with its verdict or its skip reason, this run's CONFIRMED
findings with rule code and outcome, and any ambiguity deferred with an
owner and a due date. A clean run prints the section too, with an explicit
"no findings". The run's closing commit also carries
`.claude/harness-log.jsonl`, so the record outlives the machine that made
it. On a non-GitHub forge the PR body is printed for you to paste instead.
The next `opsx-apply-git` re-syncs from your merge.

**6. On the last group**, `opsx-apply-git` archives the change via its own
PR.

---

## Components

| Skill | Gate | Purpose |
|---|---|---|
| `init-harness` | — | Scaffolder: detects stack, installs OpenSpec, writes docs/hooks; re-run after a plugin update to upgrade the repo |
| `design-system` | — (not a gate) | Writes `docs/design-system.md` — the project's one design record (tokens, primitives, state names, source) that `ui-plan` and the scaffold stage read instead of guessing UI details. Off by default (`designSystem.enabled`); manual, once per project |
| `opsx-propose-review` | 1-2 | Size the change, propose it, run architecture + clarify + spec review, build its test plan, then its UI plan if the change touches the interface |
| `opsx-scaffold` | 2b | On a change that needs one: turn `design.md`'s approved boundaries into typed stub files, confirmed with you, then reviewed |
| `opsx-apply-git` | 3-6 | Implement a run inside the branch-per-group workflow |
| `opsx-update-review` | 1-2 | Revise an existing change's plan and re-run what the revision touched |
| `architecture-review` | 1 | Boundary/coupling risk on `design.md`, against the project's accepted decisions, plus sequence diagrams for boundary-crossing flows |
| `spec-clarify` | — (before 2) | Ambiguity sweep via `devils-advocate`, resolved with you one finding at a time — edit in place, or defer with an owner and a due date |
| `spec-review` | 2 | Artifact consistency + isolated/judgement-heavy classification + the printed five-condition readiness checklist |
| `test-plan` | — (before 3) | One row per acceptance criterion: which tests close it, at which level. Gate 5's floor |
| `ui-plan` | — (not a gate) | Builds `ui-plan.md` — the screen/states/components/value-source table for a change that touches the interface, read by the scaffold stage and `opsx-apply-git` before either writes component code. Off by default, same key as `design-system` |
| `web-qa` | 3 | Real-browser QA via Playwright MCP, must-pass with a fix loop |
| `code-review` | 4-5 | Correctness + simplification, plus coverage against your test plan and configured threshold — one delegation, two labeled sections; spawns the deep review when its risk prefilter fires |
| `harness-review` | 6 | Drift/staleness in the harness config itself |
| `record-decision` | — (not a gate) | Records a decision made outside the pipeline — in chat, on a whiteboard, straight in the code — or promotes a `Proposed` record to `Accepted` |
| `debug-loop` | — (not a gate) | Bounded four-phase fix loop for a Gate 3 FAIL or a CONFIRMED finding; caps at `maxFixAttempts`, then escalates to you |
| `dead-code-report` | — (not a gate) | Finds unused files/exports/deps via knip plus the project's lint rules, sorted into three confidence groups, ending in a change-proposal draft; deletes nothing. Run manually, roughly monthly |

**`design-system` and `ui-plan` don't draw anything.** Making the mockup —
in Figma, Pencil, or on paper — stays an external tool's job; these two
skills only read it (or a text description, absent one) and write down
what already exists: tokens, primitives, screens, states, and which
components to reuse or add. Neither compares the built result against the
mockup pixel-for-pixel — that check is deliberately out of scope, caught
instead by Gate 3's real-browser QA and by human review.

### The eight subagents

They live in `agents/`, are invoked by the skills above rather than
directly, and **none of them can write to your production code** — seven
cannot write at all, and the eighth writes only tests. `debug-loop`,
`test-plan` and `record-decision` have no subagent — they run inline in the
calling session.

- `architecture-reviewer`, `code-reviewer`, `deep-reviewer`,
  `harness-reviewer` — `Read`/`Grep`/`Glob` plus `Bash`, scoped by their own
  prompts to inspection commands.
- `devils-advocate` — `Read`/`Grep`/`Glob` only, no `Bash`, no way to write:
  finding an ambiguity and resolving it are deliberately two different jobs,
  and the finder is not allowed to become an advocate for one answer.
- `web-qa-manual-tester` — no `Bash` either; `Read`/`Grep`/`Glob` plus a
  fixed list of Playwright MCP browser tools, so it is read-only on code
  while driving a real browser.
- `test-author` — the one exception, and only when you opt in
  (`makerChecker.enabled`): it has `Write`/`Edit` because writing tests is
  its whole job. It writes a task group's tests from the test plan *before*
  that group's code exists, and its own prompt confines it to test files and
  forbids it from reading the implementation it is testing.
- `spec-reviewer` — additionally carries `Edit`, limited by its prompt to
  one job: writing the `<!-- isolated -->` / `<!-- judgement-heavy -->`
  marker onto a `tasks.md` heading, which is what `opsx-apply-git` reads to
  decide what it may run unattended.

### Rules you can name and switch off

Every rule inside `code-reviewer`, `spec-reviewer`, `deep-reviewer`, and
`architecture-reviewer`'s scaffold-review mode carries a permanent code
(`CR-01`, `SR-02`, `DR-03`, `SC-1`) that never changes even when the rule's
wording does — the eight design-review checks Gate 1 runs over `design.md`
are the one exception and carry no codes. A finding names its code, so you
can dispute one rule rather than a whole gate, and `.claude/harness.json`'s
`disabledRules` array switches a single rule off while every other rule in
the same review keeps running. Without the codes the choice would be binary
— tolerate a whole gate, or disable a whole gate.

One of those codes, **`CR-13`**, checks something CR-06 doesn't: whether the
test closing a test-plan row actually reaches the level (`unit`,
`integration`, `end-to-end`) that row named, not just whether a matching
test exists.

Three of those rules are frontend-specific: **`CR-10`** (effects that start
a subscription, timer, listener or request and never tear it down),
**`CR-11`** (objects, arrays or functions rebuilt every render and handed to
a context value or a memoized child — PLAUSIBLE by default, since it's a
cost rather than a breakage, CONFIRMED when it sits in an effect's
dependency array and loops), and **`CR-12`** (the server/client boundary —
Next.js only, silent on Vite).

Exactly three, on purpose: effect dependency arrays, `any`, `key={index}`
and static accessibility are left to `react-hooks`, `@typescript-eslint`,
`jsx-a11y` and `@next/next`, which catch them deterministically, for free,
before the commit. That division is written down next to the rules
themselves, so the next release doesn't add a fourth rule duplicating a lint
rule.

---

## Command names

- **`code-review` collides with Claude Code's own built-in `/code-review`.**
  Inside the normal workflow this doesn't matter: `opsx-apply-git` runs Gate
  4 through the `Agent` tool, and the built-in couldn't be invoked that way
  anyway — it carries `disable-model-invocation` (confirmed empirically). It
  matters only when you run Gate 4 by hand, since a bare `/code-review`
  always resolves to the built-in. Use
  `/sdd-harness-web-ykryshtopa:code-review` (substitute your marketplace
  alias), or just run `/opsx-apply-git`.
- **`opsx-propose-review` / `opsx-apply-git` / `opsx-update-review` are not
  OpenSpec's own `/opsx:propose` / `/opsx:apply` / `/opsx:update`.** Once
  `init-harness` puts OpenSpec in Expanded (`custom`) profile with
  `delivery: "both"`, both sets exist side by side — this plugin's are
  hyphenated, OpenSpec's colon-namespaced. This README always means the
  hyphenated ones.

## MCP servers

- **playwright** (`@playwright/mcp`) — drives a real browser for Gate 3.
  Because it ships *inside* the plugin, Claude Code exposes its tools as
  `mcp__plugin_sdd-harness-web-ykryshtopa_playwright__browser_*` rather than
  the bare `mcp__playwright__browser_*` a project-level `.mcp.json` would
  produce, and `web-qa-manual-tester`'s `tools:` list names **only** the
  first form. It used to carry both, which quietly let the gate run against
  whatever Playwright MCP a user had configured, at whatever version — the
  opposite of what pinning `@playwright/mcp@0.0.78` is for. Disabling this
  plugin's own server therefore doesn't fall back to yours; it leaves the
  agent with nothing that resolves, so it refuses to launch, which is the
  failure you want to see rather than a browser pass on an unverified
  version.
- **context7** (`@upstash/context7-mcp`) — mandatory since 0.6.0. Used by
  `opsx-apply-git` before writing framework-specific code, and by
  `code-review` when a diff touches a library that wasn't checked at
  generation time. It works without an API key at a lower request limit, and
  being unavailable never blocks a run — the output says what failed and
  why. Trigger and mark format:
  `skills/opsx-apply-git/references/context7-lookup.md`.

If you already run your own `playwright` or `context7` MCP server, both keep
running: the two are separate servers with separately namespaced tools, so
neither shadows the other and neither changes the other's version. The only
cost is a second process, and `/mcp` disables whichever side you don't want.
`/init-harness` says so in its report when it finds a duplicate, and stays
quiet when it doesn't
(`skills/init-harness/references/mcp-duplicates.md`).

Both stay resident for the whole session even though each is used at one
point only: as of Claude Code 2.1.220 there is no supported way for a
plugin's server list to load a server per-skill or per-gate. Two things
narrow the cost — Claude Code 2.1.x defers MCP tool schemas (`ToolSearch`)
instead of loading them up front (24 tools for `@playwright/mcp@0.0.78`,
measured by asking the server itself), and `npx` resolves an already-cached
package without a registry round-trip, so installing `@playwright/mcp` as a
devDependency avoids the network check on session start. If a session won't
run `web-qa`, disable that server via `/mcp`.

These two are the only MCP servers here, and each earns its place. Notably
absent: `sequential-thinking`. `architecture-review` and `spec-review` both
run a deliberate step-by-step pass on a full-route change, and modern Claude
models cover that reasoning with native extended thinking, in one pass,
without an external round-trip per "thought".

---

## Design principle

**AI review is a sensor, not a final verdict — the human owns the merge.**
Gates 1, 2, 2b, 4 and 5 pause only on a CONFIRMED finding, and the deep review
inside Gate 4/5 pauses on exactly the same terms; PLAUSIBLE-only or clean
reviews never block. Gates 3 and 6 are must-pass/always-shown by design —
see `.claude/docs/review-gates.md` (written by `init-harness`) for the full
policy once installed.

Every review agent also states `reviewConfidence: high` or `low` for the
review as a whole, separately from CONFIRMED/PLAUSIBLE on any individual
finding. It's confidence in the review itself — enough context, no unread
dependency, nothing outside what the diff showed — not in what it found.
`low` never blocks on its own: it's a note that this pass had less to go on
than usual, worth weighing when you decide how much to trust a clean result.

## How the skills are structured

A `SKILL.md` body loads into context in full every time its skill fires; a
file under that skill's `references/` loads only when an instruction tells
the model to read it. That difference is the plugin's own cost control:

- **`SKILL.md` keeps the control flow** — every step's existence, what
  triggers it, and what makes it stop the run.
- **`references/` holds the rest** — branch-specific procedures a run may
  never take (upgrade mode, the OpenSpec profile conversation, archiving),
  and lookup material used while performing a step (the `harness.json`
  schema, the git-hook procedure, templates).

The rule that keeps the split honest: a run that never opens a single
reference still knows what it has to do and when to halt. Extracting a
*decision* would break that; extracting the detail behind one doesn't.

`tests/smoke-json-schema.sh` enforces the invariants — every reference is
reachable from its `SKILL.md`, every path a `SKILL.md` names exists (a
renamed or unreferenced file is an instruction that silently stopped running
rather than a visible error), and a line-count cap on each `SKILL.md` and
each `agents/*.md`. Today's two largest skills are grandfathered at their
current size, so the budget ratchets down and never back up. Agent files get
no grandfathering and have no `references/` escape hatch — an agent file
*is* its prompt, in full, every time — so hitting that cap is fixed by
tighter wording, never by moving a rule elsewhere.

## Versioning and releases

The version lives in **one** place, `.claude-plugin/plugin.json`. The
marketplace entry deliberately doesn't repeat it: when both are set Claude
Code silently uses the manifest's, so a stale manifest would mask the
marketplace value.

Semver, with breaking changes in the minor position until 1.0.0. Because a
declared version pins installs, the release rule is unavoidable rather than
stylistic:

1. bump `version` in `.claude-plugin/plugin.json` — every release, however
   small, or existing installs never see it;
2. add the matching `## <version>` section to `CHANGELOG.md`;
3. run `bash tests/smoke-json-schema.sh` (plus `tests/hook-behaviour.sh` and
   `tests/dead-code-scripts.sh`) — the first fails if the version isn't
   semver, if the marketplace entry has grown a competing `version`, or if
   `CHANGELOG.md` has no section for the current one;
4. `claude plugin tag --push`, **after** the release branch is merged —
   it creates the `sdd-harness-web-ykryshtopa--v<version>` git tag, having
   checked that `plugin.json` and the marketplace entry agree. That tag is
   what consumers pin with `ref`.

The alternative Claude Code offers — dropping `version` entirely so every
commit counts as a new one — is deliberately not used: this harness's whole
argument is that state should be explicit and reviewable, and "which version
am I running" is exactly that kind of state.

## The eval set

Three things measure this plugin, and the third one is new in 0.8.0:

| Layer | What it answers | Where |
|---|---|---|
| Structural tests | Are the files there and the schemas valid? | `tests/*.sh` |
| Production telemetry | What did the pipeline actually do this month? | `.claude/harness-log.jsonl`, read by `harness-stats` |
| The eval set | On a fixed list of prompts with a known right answer, did the plugin behave? | `evals/` |

The first two can both look healthy while routing quietly regresses. A
structural test never reads a skill description; the log only ever records
the skills that *did* fire, never the one that should have and didn't. And a
false fire is invisible from either side — something ran, produced output,
and read as normal.

`evals/routing/` holds 27 cases: one per skill for "this must fire", plus
eight confusable pairs and two cases where any fire is the failure.
`evals/regressions/` holds cases grown from defects that actually shipped —
`debug-loop` offers to keep one whenever a fix lands in the harness itself
rather than in project code. Format is Claude Code's own `claude plugin
eval`; there is no runner here. `evals/README.md` has the rest, including
how to check whether that command is enabled for your account — it is in
early access.

It is run by hand at three moments: after editing a skill description,
before accepting a cheaper model, and when a fixed defect becomes a case.
Not wired into any hook, and not into CI.

## Harness diet

The ratchet this plugin applies to what gets *added* — nothing new without a
real signal — has a symmetric half: checking whether what's already built has
gone stale.

A model downgrade starts with the eval set above, not with the month: measure
both models on it in one sitting, and if the cheaper one loses a case the
current one passes, the trial never starts. Then, once a month, temporarily
skip one gate's delegation (no config flag — just don't invoke it for the
trial window) or downgrade one gate's model via `.claude/harness.json`'s
`models.*`, run the normal flow of changes, and compare
`skills/harness-review/references/harness-stats.md`'s output from before and
after. No measurable difference in verdict distribution,
escalations, or `reviewConfidence: low` share → consider trimming that gate
or model for good. A real difference → put it back, and record what was
tried and found in `docs/decisions/`, with both numbers in it: accuracy on
the eval set and cost on the log. This is documented for project
consumers too, in `review-gates-template.md`.
