# sdd-harness-web-ykryshtopa

Spec-driven OpenSpec harness for web projects — **Vite or Next.js**, either
package manager (yarn/npm/pnpm), either test runner (Vitest/Jest). Six
automated review gates (five agent delegations — Gate 4 and Gate 5 share
one, see Components below), plus a security/architecture deep review that
only spawns on a diff a 0-token prefilter flags as risky; an ambiguity sweep
and a test plan before implementation starts; architecture decision records
the architecture gate actually reads back; a branch-per-group git workflow;
and a scaffolder that detects your stack instead of assuming one.

## What this is

A Claude Code plugin extracting a proven OpenSpec review harness (originally
built for a Vite + React 19 + Redux Toolkit project) into a portable,
framework-detecting form so it can be dropped into any Vite or Next.js repo.

## Requirements

- **Claude Code >= 2.1.220.** Not a soft floor — the harness is built on
  behaviour that older versions don't have or handle differently: tools from
  a plugin-bundled MCP server are named `mcp__plugin_<plugin>_<server>__<tool>`
  (Gate 3's agent resolves nothing without it); file permission rules are
  honoured for `Edit(path)`/`Read(path)` only, which is what the generated
  `permissions` block is written against (2.1.210+); a subagent whose
  `tools:` list resolves to nothing refuses to launch instead of running
  toolless (2.1.208+); and the `Stop` hook relies on `stop_hook_active`.
  2.1.220 is the version every gate, hook and manifest here was verified
  against.
- **Node >= 20.19.0** — required by OpenSpec.
- **OpenSpec configured with the `new`, `continue` and `verify` workflows.**
  This harness's gates are designed around OpenSpec's Expanded workflow set,
  not the single-shot `propose` flow that Core ships with. Note that
  `profile: custom` on its own is *not* the requirement — a custom profile
  can be missing exactly those workflows, which is what a partial pass
  through OpenSpec's interactive picker leaves behind. What matters is the
  `workflows` list, and those three names being in it. `/init-harness` checks this and offers to switch it for
  you (see Step 2 of `skills/init-harness/SKILL.md`) — but be aware that
  **this setting lives in `~/.config/openspec/config.json`, a global,
  per-machine file, not anything committed to this repository.** That means:
  - it is **not** portable between machines or teammates — everyone who
    works on this repo needs to set it up on their own machine once;
  - CI runners won't have it unless you configure it there separately;
  - switching it affects every other OpenSpec project on that machine, not
    just this one.

## Install

This repository is both the plugin and a single-plugin marketplace, so
adding it and installing from it are two steps against the same name:

```
/plugin marketplace add EvgeniyKrishtopa/sdd-harness-web-ykryshtopa
/plugin install sdd-harness-web-ykryshtopa@sdd-harness-web-ykryshtopa
```

The same commands work from a shell (`claude plugin marketplace add ...`,
`claude plugin install ...`), and `claude plugin details
sdd-harness-web-ykryshtopa` is the quickest check that it loaded: it should
list 14 skills, 7 agents by name, 3 hook events and 1 MCP server. To install
from a local checkout instead of GitHub, pass the absolute path to
`marketplace add`. There is no npm package — Claude Code installs plugins
from marketplaces, not from the npm registry.

Restart Claude Code (or `/reload-plugins`) after installing: skills take
effect immediately, but hooks, agents and MCP servers only load on start.
Then run `/init-harness` in each repository (next section) — installing the
plugin adds the skills and hooks, but writes nothing into your project. Run
it again after a `/plugin update`: the update refreshes the plugin, and
`/init-harness` is what brings the repository's own files along with it (it
detects that case itself and only fills in what's missing).

### Updating, pinning, removing

```
/plugin update sdd-harness-web-ykryshtopa      # or: claude plugin update ...
/plugin uninstall sdd-harness-web-ykryshtopa   # marketplace remove <name> to
                                               # forget the marketplace too
```

An update only arrives when this plugin's declared `version` changes —
Claude Code caches by resolved version and skips a plugin whose version it
already has. That means a fix pushed without a version bump reaches nobody;
see "Versioning and releases" below for how that's handled here, and
`CHANGELOG.md` for what each version changed.

To hold a specific release rather than tracking the default branch, point
your own marketplace entry at a tag or commit:

```json
{
  "name": "sdd-harness-web-ykryshtopa",
  "source": {
    "source": "github",
    "repo": "EvgeniyKrishtopa/sdd-harness-web-ykryshtopa",
    "ref": "sdd-harness-web-ykryshtopa--v0.5.0"
  }
}
```

## Versioning and releases

The version lives in **one** place, `.claude-plugin/plugin.json`. The
marketplace entry deliberately doesn't repeat it: when both are set Claude
Code silently uses the manifest's, so a stale manifest would mask the
marketplace value.

Semver, with breaking changes in the minor position until 1.0.0. Because a
declared version pins installs, the rule is unavoidable rather than
stylistic:

1. bump `version` in `.claude-plugin/plugin.json` — every release, however
   small, or existing installs never see it;
2. add the matching `## <version>` section to `CHANGELOG.md`;
3. `bash tests/smoke-json-schema.sh` (plus `tests/hook-behaviour.sh` and
   `tests/dead-code-scripts.sh`) — the first fails if the version isn't semver,
   if the marketplace entry has grown a competing `version`, or if
   `CHANGELOG.md` has no section for the current one;
4. `claude plugin tag --push` — creates the `sdd-harness-web-ykryshtopa--v<version>`
   git tag, after checking that `plugin.json` and the marketplace entry
   agree. That tag is what consumers pin with `ref`.

The alternative Claude Code offers — dropping `version` entirely so every
commit counts as a new one — is deliberately not used here: this harness's
whole argument is that state should be explicit and reviewable, and "which
version am I running" is exactly that kind of state.

## Keeping a configured repository in step with the plugin

**`/plugin update` only refreshes the plugin itself** — its skills, agents,
and hooks. It writes nothing into your repository. Every release that adds a
file or a manifest key therefore needs a second step in each repo that uses
the harness, and the step is always the same one:

```
/init-harness
```

It reads `.claude/harness.json`'s `harnessVersion` and compares it against
the installed plugin's own `version`. Absent or lower means an
already-configured repo, so it switches to **upgrade mode** instead of
re-running the first-time questionnaire: it fills in only what's actually
missing — new files, new manifest keys, new rules appended to an existing
`openspec/config.yaml` list — and never overwrites a file you may have
customized without showing you the diff and asking first. On a repo already
at the current version it says so plainly and changes nothing.

The list of what upgrade mode owns lives in one place,
`skills/init-harness/references/upgrade-mode.md`, and every release that
teaches the scaffolder to write something new adds its row there in the same
commit. That inventory is also what Gate 6 (`harness-review`) checks your
repo against, so a repo that fell behind surfaces as a finding rather than
as a check quietly reporting "not applicable" forever.

## First run

```
/init-harness
```

Detects your framework, package manager, and test runner; installs and
initializes OpenSpec in Expanded profile, seeding `openspec/config.yaml`
with your project's detected context and artifact rules; asks for your
coverage threshold; writes `.claude/docs/git-conventions.md`,
`.claude/docs/review-gates.md`, and `.claude/docs/laziness-ladder.md`; seeds
`PROGRESS.md` and `.gitattributes` (`PROGRESS.md merge=union`, so every
task-group branch in this harness's branch-per-group workflow can touch it
without conflicting) — `docs/decisions/` isn't created here; it appears
later, on demand, the first time a decision actually outlives its change;
writes `.claude/harness.json` — the single machine-readable manifest every
other skill and hook in this plugin reads instead of re-detecting your
stack, including `maxFixAttempts` (the `debug-loop` skill's fix-attempt cap
before it escalates to you) — then **proves the detected toolchain actually
runs**: the typecheck, lint, and coverage scripts are executed for real, not
just detected, and only once all three genuinely pass does it write
`harnessVersion` and `toolchainVerifiedAt`, the two keys that record a repo
as fully configured for this plugin version; creates or appends a short
pointer block in `CLAUDE.md`/`AGENTS.md` so that those docs (and the
auto-commit override they define) are actually discoverable — Claude Code
doesn't load `.claude/docs/*.md` into context on its own the way it loads
`CLAUDE.md`; merges a full `permissions` allow/deny list into your
`.claude/settings.json`; writes `.claudeignore` plus its enforcement hook;
installs native git hooks via Husky — `.husky/pre-commit` (typecheck + lint
+ `lint-staged`, kept fast since it fires once per task group) and
`.husky/pre-push` (the full `test:coverage` run, then a blocking
dependency-vulnerability audit) — independent of Claude Code's own hooks, so
bad commits and pushes are still blocked even with no agent involved.

This plugin's own Claude Code hooks (`hooks/hooks.json` — commit/merge/push
guards, `.claudeignore` enforcement, typecheck-before-stop, and a
`SessionStart` banner printing branch/status/recent commits, plus — once
`PROGRESS.md` exists — its `Status` and `Next steps` sections, so a new
session's first read answers what `git log` alone can't) apply automatically
to any repo where the plugin is enabled, the same way its skills and agents
do. The commit/merge/push guards are plain shell — they
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

1. `/opsx-propose-review` — propose a change. Before any artifact exists it
   sizes the change from three observable questions (more than one module? a
   data-schema change? a contract change?) and records `short` or `full` in
   `openspec/changes/<change>/.route`. Then Gate 1, then — on the full route
   — `spec-clarify`, which sweeps the drafted artifacts for wording two
   engineers would read two ways and closes each finding with you one
   question at a time, then Gate 2, then `test-plan`. You end up with a
   change whose ambiguities are resolved, whose readiness is a printed
   five-condition checklist rather than a phrase, and whose every acceptance
   criterion already has a planned test.
2. `/opsx-apply-git` — implement the next run: an autonomous batch of
   `isolated` groups to one PR, or one `judgement-heavy` group with you in
   the loop. A decision that crosses the recording threshold (irreversible,
   multi-module, or had live alternatives) gets written to `docs/decisions/`
   from *either* branch — `Proposed` from an autonomous group, `Accepted`
   when you were in the loop — and Gate 1 reads the accepted ones back on
   every later change.
3. Each group implements and commits as it goes; Gates 3-6 (`web-qa` →
   `code-review` [Gate 4 + Gate 5 in one delegation] → `harness-review`) run
   automatically once per run, after every group in it is already
   committed and before push — not once per group — per
   `.claude/docs/review-gates.md`. Gate 3 checks every user-facing surface
   against a required UI States Matrix (loading/error/empty/offline, plus
   syncing/conflict where a project actually has background sync), taking
   the states from `design.md`'s sequence diagram for that flow when one
   exists; Gate 5 checks written tests against the change's own test plan,
   falling back to a grep over its `FR-`/`NFR-` identifiers when it has
   none — an uncovered ID surfaces by name before `code-reviewer` even runs.
   Inside the same step, a 0-token prefilter greps the diff for risk signals
   (auth, permissions, payments, migrations, config, secrets, uploads) and
   spawns `deep-reviewer` for a security and architecture-as-built pass only
   when one fires; most runs skip it, and the skip is logged. A `web-qa`
   FAIL or a `code-review`/deep-review CONFIRMED finding you choose to fix
   runs through `debug-loop` — a bounded, four-phase fix loop that escalates
   to you instead of retrying forever, leaves a written record of every
   hypothesis under `_debug/`, and classifies the fixed defect against the
   specification so a missing acceptance criterion gets added rather than
   silently staying missing.
4. You merge each run's PR on GitHub; the next `opsx-apply-git` re-syncs
   from that merge.
5. On the last group, `opsx-apply-git` archives the change via its own PR.

## Components

| Skill | Gate | Purpose |
|---|---|---|
| `init-harness` | — | Scaffolder: detects stack, installs OpenSpec, writes docs/hooks; re-run after a plugin update to upgrade the repo |
| `opsx-propose-review` | 1-2 | Size the change, propose it, run architecture + clarify + spec review, then build its test plan |
| `opsx-apply-git` | 3-6 | Implement a run inside the branch-per-group workflow |
| `opsx-update-review` | 1-2 | Revise an existing change's plan and re-run what the revision touched |
| `architecture-review` | 1 | Boundary/coupling risk on `design.md`, against the project's accepted decisions, plus sequence diagrams for boundary-crossing flows |
| `spec-clarify` | — (before 2) | Ambiguity sweep via `devils-advocate`, resolved with you one finding at a time — edit in place, or defer with an owner and a due date |
| `spec-review` | 2 | Artifact consistency + isolated/judgement-heavy classification + the printed five-condition readiness checklist |
| `test-plan` | — (before 3) | One row per acceptance criterion: which tests close it, at which level. Gate 5's floor |
| `web-qa` | 3 | Real-browser QA via Playwright MCP, must-pass with a fix loop |
| `code-review` | 4-5 | Correctness bugs + simplification, AND coverage gaps against your test plan and configured threshold — one delegation, two labeled sections; spawns the deep review when its risk prefilter fires |
| `harness-review` | 6 | Drift/staleness in the harness config itself |
| `record-decision` | — (not a gate) | Writes down a decision made outside the pipeline — in chat, on a whiteboard, straight in the code — or promotes an existing `Proposed` record to `Accepted` |
| `debug-loop` | — (not a gate) | Bounded, four-phase fix loop for a `web-qa` FAIL or a `code-review` CONFIRMED finding you chose to fix; caps at `maxFixAttempts` and escalates to you instead of retrying forever |
| `dead-code-report` | — (not a gate) | Finds unused files/exports/deps via knip plus the project's own lint rules, sorts findings into three confidence groups, ends with a change-proposal draft; never deletes anything. Run manually, roughly monthly |

Seven matching subagents live in `agents/` and are invoked by the skills
above, not usually directly — `debug-loop`, `test-plan` and
`record-decision` have no subagent of their own; they run inline in the
calling session. None of the seven can write to your source. Four
(`architecture-reviewer`, `code-reviewer`, `deep-reviewer`,
`harness-reviewer`) are `Read`/`Grep`/`Glob` plus `Bash`, scoped by their
own prompts to inspection commands; `devils-advocate` is `Read`/`Grep`/
`Glob` only, with no `Bash` and no way to write — finding an ambiguity and
resolving it are deliberately two different jobs, and the finder is not
allowed to become an advocate for one answer; `web-qa-manual-tester`
carries no `Bash` at all either — it gets `Read`/`Grep`/`Glob` plus a fixed
list of Playwright MCP browser tools, so it is read-only on code while
driving a real browser; `spec-reviewer` additionally carries `Edit`,
limited by its prompt to one job — writing the `<!-- isolated -->` /
`<!-- judgement-heavy -->` marker onto a `tasks.md` heading, which is what
`opsx-apply-git` reads to decide what it may run unattended.

Every rule inside `code-reviewer`, `spec-reviewer` and `deep-reviewer`
carries a permanent code (`CR-01`, `SR-02`, `DR-03`) that never changes even
when the rule's wording does. A finding names its code, so you can dispute
one rule rather than a whole gate, and `.claude/harness.json`'s
`disabledRules` array switches a single rule off while every other rule in
the same review keeps running. Without the codes the choice would be binary
— tolerate a whole gate, or disable a whole gate.

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
  (`ToolSearch`) rather than loading all of Playwright's tools into context
  up front — 24 of them, as of `@playwright/mcp@0.0.78`, measured by asking
  the server itself — so the static footprint is smaller than a naive count
  suggests; (2) `npx` resolves an already-cached/locally-installed package
  without a registry round-trip, so a project that installs
  `@playwright/mcp` as a devDependency (rather than relying on `npx -y` to
  fetch it fresh) avoids the network check on session start. Neither
  eliminates the server being resident for gates 1/2/4/5/6, which never
  touch a browser — if a session is known not to run `web-qa`, disable the
  server for it via `/mcp` (or remove/comment the entry from `.mcp.json` in
  a project fork) rather than leaving it attached by default.

Playwright is the only MCP server here on purpose. `architecture-review` and
`spec-review` both run a deliberate step-by-step pass on a full-route change,
and neither reaches for a `sequential-thinking` server to do it: modern
Claude models have native extended thinking that covers the same reasoning in
one pass, without an external tool round-trip per "thought"
(cost-optimization #39).

## Design principle

AI review is a sensor, not a final verdict — the human owns the merge.
Gates 1, 2, 4, 5 pause only on a CONFIRMED finding, and the deep review
inside Gate 4/5 pauses on exactly the same terms; PLAUSIBLE-only or clean
reviews never block. Gates 3 and 6 are must-pass/always-shown by design —
see `.claude/docs/review-gates.md` (written by `init-harness`) for the full
policy once installed in your repo.

Every review agent also states `reviewConfidence: high` or `low` for the
review as a whole, separately from CONFIRMED/PLAUSIBLE on any individual
finding — it's confidence in the review itself (enough context, no unread
dependency, nothing outside what the diff showed), not in what it found.
`low` never blocks on its own; a clean, low-confidence review still passes.
It's a narrower signal than a verdict: a note that this particular pass had
less to go on than usual, worth weighing if you're deciding how much to
trust a clean result rather than a reason to distrust the harness broadly.

## How the skills themselves are structured

A `SKILL.md` body loads into context in full every time its skill fires. A
file under that skill's `references/` loads only when an instruction tells
the model to read it. That difference is the plugin's own cost control, and
it is applied deliberately:

- **`SKILL.md` keeps the control flow** — every step's existence, what
  triggers it, and what makes it stop the run.
- **`references/` holds the rest** — branch-specific procedures a given run
  may never take (upgrade mode, the OpenSpec profile conversation,
  archiving), and lookup material consulted while performing a step (the
  `harness.json` schema and field notes, the git-hook procedure, templates).

The rule that keeps the split honest: a run that never opens a single
reference still knows what it has to do and when to halt. Extracting a
*decision* would break that; extracting the detail behind one doesn't.

`tests/smoke-json-schema.sh` enforces two invariants here — every reference
is reachable from its `SKILL.md`, and every path a `SKILL.md` names exists —
because an unreferenced or renamed reference is an instruction that silently
stopped running rather than a visible error. It also caps each `SKILL.md`'s
line count, with today's two largest grandfathered at their current size, so
the budget ratchets down and never back up.

## Harness diet

The ratchet principle this plugin applies to what gets *added* — nothing
new without a real signal — has a symmetric half: checking whether what's
already built has gone stale. Once a month, temporarily skip one gate's
delegation (no config flag for this — just don't invoke it for the trial
window) or downgrade one gate's model via `.claude/harness.json`'s
`models.*`, run the normal flow of changes, and compare
`skills/harness-review/references/harness-stats.md`'s output from before
and after. No measurable difference (verdict
distribution, escalations, `reviewConfidence: low` share) → consider
trimming that gate or model for good. A real difference → put it back and
record what was tried and found as a new file in `docs/decisions/`. This is
documented for project consumers too, in `review-gates-template.md`.
