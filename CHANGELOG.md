# Changelog

This plugin declares a `version` in `.claude-plugin/plugin.json`, which
means Claude Code pins installs to that string: pushing commits without
bumping it delivers nothing to anyone who already installed. Every release
therefore gets a version bump and an entry here. See "Versioning and
releases" in the README for the procedure.

Versions follow semver. Before 1.0.0, breaking changes land in the minor
position.

## 0.7.0

**Run `/init-harness` again, in upgrade mode, after updating this plugin,
or the new stage stays off.** `.claude/harness.json` gains a `scaffold` key
this release, and unlike every other flag it added before, a missing key
(or `enabled: false`) means the new stage does **not** run — a repository
last configured by an earlier plugin version won't have a new step sprung on
it the moment the plugin updates. Upgrade mode seeds the key `{"enabled":
true}`; turn it back off in `.claude/harness.json` afterward if you don't
want the stage.

A `design.md` can describe a boundary in words — "data fetching lives in the
access layer" — without saying where the files actually go, and nothing
catches the gap until code review, when the feature is already written and
fixing it means moving files instead of editing a line. This release adds a
stage between proposing a change and implementing it that turns an
already-approved `design.md` into real files first: typed signatures at
their final paths, stub bodies only, no logic.

### Added — the scaffold stage

- **A new skill, `opsx-scaffold`.** On a change whose proposal step judged
  it needs one, it reads `design.md`'s already-approved boundaries, draws a
  file map (path / responsibility / export), confirms it with you in one
  question, then creates the files as typed stubs and runs typecheck and
  lint. It never reopens the architecture — that stays Gate 1's job; the
  only question here is whether the file map is correct. Runs on its own
  branch, one commit, merged before the change's first task group starts.
- **`opsx-propose-review` now also computes a `.scaffold` marker**
  (`openspec/changes/<change>/.scaffold`, `yes` or `no`) alongside the
  existing `.route` marker, from two observable questions — does the change
  add a new module, or a new boundary crossing? — asked only when the
  manifest's `scaffold` key is enabled. `no`, or the file missing, sends the
  change straight to `opsx-apply-git` as before; the everyday workflow for a
  change that doesn't need a scaffold does not change at all.
- **A "Scaffold map" section in `design.md`**, written by `opsx-scaffold`
  once the files exist, not before — real paths and real exports rather than
  a plan. No new per-change document.
- **Gate 2b — scaffold-review.** `architecture-reviewer` gains a
  scaffold-review mode (rules `SC-1`..`SC-6`) that checks the scaffold's
  layout, signatures and imports against `design.md`'s already-approved
  boundaries — never the architecture itself. It runs only when a change's
  own `.scaffold` marker is `yes` and the manifest has the stage enabled;
  otherwise no scaffold-review line is logged at all. The eight existing
  `architecture-reviewer` rules over `design.md` itself are untouched.
- **`scaffold` in `.claude/harness.json`** — a single `enabled` toggle for
  the whole stage. See the upgrade note above for why its default runs
  backwards from every other manifest flag.

### Changed — the pipeline is seven gates now

- README and the plugin description both said six automated review gates;
  both now say seven, and name the scaffold check alongside the rest.

## 0.6.2

Gate 3 and the context7 lookup now run on the servers this plugin pins,
instead of quietly accepting whichever copy the user happens to have
configured. Both holes were the same shape: the version was pinned in
`.mcp.json`, and then the instructions named a tool that belongs to a
different server.

### Fixed — the pinned servers are the ones actually used

- **`web-qa-manual-tester` lists only the plugin-namespaced browser tools.**
  It used to carry each of the eleven twice — once as
  `mcp__plugin_sdd-harness-web-ykryshtopa_playwright__browser_*`, once bare.
  The bare spelling is a *different* server, supplied by the project or the
  user at whatever version they asked for, frequently `@latest`. The
  fallback made a browser pass on an unverified Playwright possible without
  anyone noticing. Disabling the plugin's own server now leaves nothing that
  resolves, so the agent refuses to launch — a loud failure in place of a
  quiet one. All eleven names were confirmed against a live server, and a
  real browser pass was driven end to end against
  `tests/fixtures/vite-vitest-yarn`.
- **The context7 lookup names the plugin's own tools.**
  `references/context7-lookup.md` said to call `mcp__context7__*`, which is
  the user's server if they have one and nothing at all if they don't. It
  now names
  `mcp__plugin_sdd-harness-web-ykryshtopa_context7__{resolve-library-id,query-docs}`,
  pinned to `@upstash/context7-mcp@4.0.0`.

### Changed — the server list is no longer `.mcp.json`

- **It lives in `mcp-config.json`, named by `plugin.json`'s `mcpServers`
  key.** A file called `.mcp.json` in the plugin's root doubles as *this
  repository's* project MCP config, which requires an `mcpServers` wrapper
  and reported `Invalid input: expected record, received undefined` on every
  `claude mcp list`. Consumers never saw it; the plugin's own diagnostics
  carried a permanent red line, which is how a real one gets missed. The
  content also moved to the documented wrapper shape. Both shapes load — the
  bare one was verified working before the change — so this is about
  readable diagnostics, not a broken load.

### Added — the report names a duplicate server

- **`init-harness` says so when you already run your own `playwright` or
  `context7`.** They coexist, tools are namespaced apart, the harness uses
  its own pinned copy, and `/mcp` disables either side; the only cost is a
  second process. Found nothing, or `claude mcp list` unavailable → it says
  nothing. `references/mcp-duplicates.md` also records the two things not to
  say: that the user must remove theirs, and that disabling the plugin's own
  copy is equivalent.

### Fixed — a test that failed for the wrong reason

- **`hook-behaviour.sh` drops `node_modules` when copying the fixture.**
  The fixture is a runnable app, so a live browser pass leaves dependencies
  behind; they are gitignored, invisible in `git status`, and a real
  `node_modules/.bin/tsc` in the copy makes the Stop hook's
  "no manifest and no local tsc" case unreachable. The suite went red with
  nothing about the plugin changed.

## 0.6.1

The `Claude Code >= 2.1.220` requirement is now checked, not just written
down. It sat in the README where nothing enforced it, so an install on an
older version was recorded as fully configured while the four behaviours the
harness leans on — plugin-bundled MCP tool names, `Edit(path)`/`Read(path)`
permission rules, a subagent refusing to launch with unresolvable `tools:`,
and `stop_hook_active` — failed silently instead of loudly.

The plugin format offers no place to declare a minimum host version:
`requirements` in `plugin.json` validates as an unknown key Claude Code
ignores at load time. So the check happens in the two places that can
actually run.

### Added — the version floor is enforced twice

- **`init-harness` checks it before Step 0** and stops without writing a
  single file when the running version is below the floor — the same shape
  as the existing Node check, for the same reason: a repo half-configured
  against an unsupported runtime is worse than one not configured at all.
  Procedure and reasoning in the new
  `skills/init-harness/references/claude-code-version.md`.
- **The `SessionStart` hook re-checks every session**, printing a two-line
  warning above the git banner. Setup runs once per repository; the version
  can change under it any day after that, and a repo configured months ago
  would otherwise never look again.
- **The version is read from `CLAUDE_CODE_EXECPATH` before `PATH`** — that
  is the binary hosting the session, which can be an older install than the
  `claude` on `PATH` — and compared with `sort -V`, so `2.1.9` doesn't read
  as newer than `2.1.220`.
- **Unreadable version behaves differently in the two places, on purpose.**
  Setup prints one explicit "skipped, and why" line and continues; the
  banner prints nothing. A warning shown every session in every repository,
  for what is usually a `PATH` quirk, trains people to ignore the banner.
- **The floor is one number in three files**, so `smoke-json-schema.sh` now
  asserts the reference, the hook and the README agree on it, and
  `hook-behaviour.sh` drives all three branches through a stub binary.

## 0.6.0

**context7 is now a mandatory dependency of this plugin**, declared in its
own `.mcp.json` next to Playwright. It installs and starts with the plugin —
nothing to set up separately, and no API key is required (without one it
runs at a lower request limit).

Two halves. The first makes the plugin honest about what it does *not* do:
it was written for GitHub only and said nothing about it, and it let a repo
with no continuous build at all believe the harness covered that too. The
second closes the gap the first-line promise opened — "a harness for Vite
and Next.js" whose twenty review rules would apply unchanged to a backend
in another language. Nine items.

### Added — the plugin says what it doesn't cover

- **The code forge is detected, recorded, and warned about.**
  `init-harness` reads `git remote get-url origin` and writes
  `.claude/harness.json`'s new `forge` key — `"github"` or `"other"`, two
  values because this harness's delivery step fails identically on GitLab,
  Bitbucket and Azure DevOps. On `"other"` setup says so in one paragraph
  and finishes normally; the repo is fully configured, it just loses one
  step. At delivery, `opsx-apply-git` reads the same key: `"github"` opens
  the PR through `gh pr create` exactly as before, `"other"` skips `gh` and
  prints the branch, the target branch and the composed PR body for you to
  paste. Archiving asks you whether the run's PR merged instead of calling
  `gh pr view`.
- **Gate 6 notices a missing continuous build.** One presence check for
  `.github/workflows/*.yml|yaml`, `.gitlab-ci.yml`,
  `bitbucket-pipelines.yml` or `azure-pipelines.yml` — found, and it says
  nothing; absent, and it reports once per run that quality here is
  verified only on whichever machine runs this harness. It never opens the
  file it finds, never grades it, and never names a file to create: this
  plugin does not write a continuous-build description for any forge, and
  reading one to judge it would take that decision back through a side
  door.

### Added — the review leaves a trail

- **A second section in every PR body, "Review trail"**, right after "What
  changed and why": a link to `openspec/changes/<name>/`, one line per each
  of the six checks with its verdict (or its skip reason, from the closed
  list already in the journal), this run's CONFIRMED findings with rule
  code and outcome, and the ambiguities deferred with an owner and a due
  date. PLAUSIBLE notes stay out on purpose, more than ten findings prints
  ten plus a pointer to the journal, and a clean run prints the section too
  with an explicit "no findings" — a section that appears only when
  something was found is indistinguishable from one that stopped being
  printed. No new journal field: it is assembled from what the pipeline
  already writes.
- **`.claude/harness-log.jsonl` is committed with the run.** It was a local
  file nine writers appended to and nobody staged, which is also what made
  the monthly harness-diet comparison meaningless. `init-harness` now seeds
  `.gitattributes` with `.claude/harness-log.jsonl merge=union` (the same
  treatment `PROGRESS.md` gets, for the same reason), and the run's closing
  commit carries the journal. Nothing trims it automatically — that button
  stays out, same call as 0.5.0.

### Added — the code review knows it is reviewing a frontend

- **A line-count cap on `agents/*.md`**, 200 lines, checked by
  `tests/smoke-json-schema.sh` with no grandfathered exceptions. Introduced
  *before* the rules below, so the cap is a limit rather than a
  rubber-stamp of whatever the files grew to. An agent file has no
  `references/` escape hatch the way a `SKILL.md` does — it is its prompt,
  in full, every time — so the fix for hitting the cap is tighter wording,
  which is written next to the check.
- **`init-harness` reports which linter rule sets the project is missing** —
  `react-hooks`, `jsx-a11y`, `@typescript-eslint` always, `@next/next` on
  Next.js only — naming what each one stops catching. A recommendation, not
  a requirement: it installs nothing, writes nothing into your linter
  config, and never stops setup. A project on Biome (or with no linter
  config) gets one explicit line saying the check was skipped and why,
  because silence there reads exactly like a pass. Gate 6 reports the same
  list on every later review, from the same single file, so a rule set
  dropped later doesn't go unnoticed.
- **Three frontend rules in `code-reviewer`: `CR-10`, `CR-11`, `CR-12`.**
  Effect cleanup and lifecycle leaks; unstable references crossing a
  component boundary (PLAUSIBLE by default — it is a cost, not a breakage —
  CONFIRMED only when the unstable value sits in an effect's dependency
  array and loops); and the server/client boundary, which fires only when
  the manifest's `framework` is Next.js and stays entirely silent on Vite.
  Exactly three, because the five classes a linter catches deterministically
  and for free are left to the linter — written down next to the rules so
  the next release doesn't add a fourth that duplicates a lint rule.
- **A required keyboard pass in Gate 3**, per user-facing surface, beside
  the UI States Matrix rather than inside it: the primary action reachable
  without a mouse, focus visible at each step, a sensible tab order, and a
  modal that traps focus and closes on Escape. PASS / FAIL /
  not-applicable-with-a-reason, never a silent skip — and a FAIL blocks the
  run into `debug-loop` like any other Gate 3 failure, because a check that
  only prints is a check that gets skipped.

### Added — current library docs, at generation and at review

- **context7 is consulted before framework-specific code is written**, and
  again at code review when the diff touches a library that wasn't checked.
  One trigger list, one mark format, two readers
  (`skills/opsx-apply-git/references/context7-lookup.md`): a task naming a
  library or framework-specific API gets the lookup before the first line
  of code, and the group's commit message carries `context7: <name>
  checked`. Gate 4's own 0-token diff scan reads that mark and does not ask
  twice. The result reaches `code-reviewer` as further evidence for `CR-01`
  — not a new rule code. Unavailable at either point, the work continues
  and the output says plainly what failed and why; a silent skip is not
  allowed. Nothing about this touches the journal — it is not one of the
  six checks.

## 0.5.0

**Every repository `init-harness` already configured must run
`/init-harness` again, in upgrade mode, after updating this plugin.** This
is a breaking change on the same grounds 0.3.0 was: `/plugin update`
refreshes the plugin only, and until upgrade mode runs in your repository it
has no `CONTEXT.md` glossary, no Given/When/Then rule in
`openspec/config.yaml`, and none of the four new `.claude/harness.json`
keys — so several of the checks below silently mark themselves *not
applicable* instead of running. Breaking changes land in the minor position
before 1.0.0, which is why this is 0.5.0 and not 0.4.2.

The file-by-file list, all of it written by upgrade mode:

- **`CONTEXT.md`** at the repo root — the project glossary, created empty
  (heading only) and filled in as terms come up. Without it,
  `spec-reviewer`'s `SR-05` and two of `spec-review`'s five readiness
  conditions report *not applicable* on every run.
- **A Given/When/Then rule appended to `openspec/config.yaml`'s existing
  `rules.proposal` list.** Without it OpenSpec keeps drafting free-form
  acceptance criteria and the form check has nothing to check.
- **Four `.claude/harness.json` keys** — `disabledRules`, `sizeRouting`,
  `models.clarify`, `models.deep`.
- **A `CONTEXT.md` pointer** appended to the `CLAUDE.md`/`AGENTS.md` block,
  without which the glossary never reaches a session's context.

The per-change files this release adds —
`openspec/changes/<change>/.route`, `test-plan.md`, and the `_debug/`
records — need nothing here; the skills that own them create them on demand
on the next change you propose.

Through 0.4.1 this plugin reviewed a specification well and helped write one
not at all. Documents were generated by OpenSpec in a single shot and went
straight to review, with no question asked of you in between — everything
the model didn't know, it decided for you, silently and unmarked. Decision
records had the same shape of problem from the other end: they could only be
written in one of the two work branches, and nothing ever read them back.
This release brings the specification-and-decision half of the harness up to
the level the code-review half already had. Fourteen items, in six groups.

The ideas come from the `sdd` skill set, taken as separate mechanisms rather
than as a methodology — the same call already made for `superpowers`,
`ponytail` and `clear-progress`. One constraint shaped all fourteen: this
plugin does not generate specification documents, OpenSpec does. What is
borrowed is everything *around* the document — the interview, the critique,
the threshold for recording a decision, the tie between tests and acceptance
criteria — never a second command that writes a `proposal.md`.

### Added — a shared language and a checkable form

- **`CONTEXT.md`, a project glossary**, created empty by `init-harness` at
  the repo root and pointed at from `CLAUDE.md`. One line per domain term,
  in two required parts: the definition, and what it must *not* be confused
  with and why. The second part is not decoration — a term is disputed
  because of a neighbouring term, not in isolation. `spec-reviewer` reads it
  on every run (`SR-05`) and reports a term used against its glossary
  meaning as a CONFIRMED finding. Generic technical vocabulary (request,
  cache, queue) is explicitly out of scope.
- **Acceptance criteria are now Given/When/Then**, as a rule seeded into
  `openspec/config.yaml` next to the existing requirement-identifier rule.
  This is a deliberate exception to the plugin's own "don't impose a house
  style on a proposal" rule, admitted on the one ground that rule allows:
  without a form, there is nothing for a check to check. `spec-reviewer`
  (`SR-02`) now reports a missing When or Then as CONFIRMED and names which
  part is absent — a form check, not a judgement about the wording — and
  `code-reviewer`'s coverage check matches a test against a concrete Then
  line instead of a paragraph.
- **Every rule in `code-reviewer`, `spec-reviewer` and the new
  `deep-reviewer` carries a permanent code** (`CR-01`, `SR-02`, `DR-03`),
  which never changes even when the rule's wording is rewritten. A finding
  names its code, so you can argue with one rule instead of with "the code
  review", and `.claude/harness.json`'s new `disabledRules` array switches
  a single rule off while every other rule in the same review keeps running.
  The code is also written to the journal's `kind: "finding"` line — the
  one journal field this release adds, added everywhere the line is written
  and read plus the test, in the same commit. The per-rule report that would
  read those numbers back is deliberately *not* here: it would be counting
  an empty journal today. It is deferred, with its return condition, in
  `harness-audit/deferred-ideas.txt`.

### Added — the specification gets questioned before work starts

- **`devils-advocate`, a read-only agent with exactly one job**: find the
  places where two competent engineers would read the same sentence and
  build different things. It runs on a clean context on purpose — an agent
  that remembers what it meant reads its own memory back off the page. It
  proposes no fixes and cannot write; each finding is a file:line, the
  quoted text, and two defensible readings.
- **`spec-clarify`, a new step between drafting and review**, which takes
  those findings and closes every one of them *with you*, one question at a
  time — a list of seven questions gets seven inattentive answers. Two
  outcomes exist and no third: **clarify**, which edits the specification on
  the spot, or **defer**, which writes the question under `proposal.md`'s
  Open Questions with an owner and a due date. A deferred entry missing
  either is not written. "Looked at it and moved on" is not an outcome.
- **`spec-review` prints an explicit five-condition readiness checklist**,
  on every run — clean or not; a list shown only on failure is a list nobody
  reads. Artifacts done · every `FR-`/`NFR-` traced · every task group
  classified · no ownerless open question · no term contradicting the
  glossary. An unmet condition is named individually, never as a generic
  "not ready", and gets its own journal line. On a repository not yet
  upgraded the last two mark themselves *not applicable* rather than failing.

### Added — decisions that get written, and read back

- **A decision is recorded by a threshold, in both work branches.** The bar:
  irreversible or expensive to reverse, touches more than one module, or had
  live alternatives someone could reasonably have picked. Until now a record
  could only be born in a judgement-heavy group — whether a decision
  survived depended on how the task group happened to be classified, which
  was decided on entirely unrelated grounds. An autonomous group now writes
  the record as **Proposed** and keeps going; a human promotes it to
  **Accepted**. Below the bar, still no file: the threshold works in both
  directions or the folder fills with noise in a week.
- **`record-decision`**, a new skill for the decisions made outside the
  pipeline entirely — in chat, on a whiteboard, straight in the code. Those
  exist always and had nowhere to go, since the only writing point was
  buried inside another skill's step. It also detects that a `Proposed`
  record already covers the decision and promotes it instead of writing a
  second file.
- **`architecture-review` reads the accepted decisions before it reviews
  anything.** The word "decisions" did not appear in `architecture-reviewer`
  at all before this release: the gate analysed a design knowing not one
  decision ever made on the project — precisely the situation decision
  records are supposed to prevent. It now reads titles and `## Status` /
  `## Decision` ranges only (a project with fifty records would otherwise
  spend the whole review budget here), opens a full file only where a
  contradiction is suspected, skips `Proposed` and superseded records, and
  reports a contradiction as CONFIRMED citing the decision by number. No
  decisions folder → the step is skipped silently.

### Added — the specification stays tied to the work

- **Sequence diagrams for boundary-crossing flows.** `design.md` is expected
  to carry a Mermaid `sequenceDiagram` per flow that crosses a system
  boundary (browser↔server, server↔external service), with a happy path
  *and* its error branches. Mermaid because it is text: it renders in a
  preview and reads to a model, which a picture doesn't.
  `architecture-reviewer` raises two separate findings — no diagram, and a
  diagram with no error branches — because they are different defects. Calls
  between modules on one side of a boundary need none; that would be noise.
  Gate 3 (`web-qa`) now takes a surface's states from the diagram covering
  it, instead of guessing them from the change list.
- **`test-plan`, a coverage table written before implementation starts** —
  one row per acceptance criterion: requirement identifier, the tests that
  close it, and the level (unit / integration / end-to-end, never a
  test-runner name, since this plugin supports two). Gate 5 then compares
  plan against fact instead of judging sufficiency by impression: a plan row
  with no test is CONFIRMED, and a test beyond the plan is never a finding —
  the plan is a floor, not a ceiling. On the short route the table goes into
  `proposal.md` rather than a separate file.
- **A fixed defect is classified against the specification** before
  `debug-loop` reports success — three cases: the criterion exists and was
  violated (a regression; pin it with a test, the spec is untouched), the
  criterion exists but was ambiguous (fix the wording), or no criterion
  covered the behaviour at all (add one, tagged `(added by defect fix)`).
  The third is the most common and the least comfortable: it means the
  change shipped with a hole in its requirements. The classification happens
  inline in the same conversation — no additional agent run — and the spec
  edit is committed separately from the code fix.

### Added — cost, and depth where it is earned

- **Size-based routing.** Every other item in this release *adds* steps to a
  change's path; this one subtracts. Before any artifact exists,
  `opsx-propose-review` answers three purely observable questions — more
  than one module, a data-schema change, a change to a contract other code
  depends on — and writes `short` or `full` to
  `openspec/changes/<change>/.route`. The short route skips the ambiguity
  sweep and the two gates' extra deliberation pass, and writes the test plan
  into the proposal instead of a separate file. What it never skips is code
  review or coverage: the saving is on documents, never on checking the
  result. The route is one editable line, because an estimate made before
  any code exists is easy to get wrong. `sizeRouting.enabled: false` turns
  the assessment off entirely.
- **`deep-reviewer`, a security and architecture-as-built pass** on top of
  Gates 4/5. This plugin had no security review of any kind — nine rules in
  `code-reviewer`, not one of them about security; the only mention of the
  word anywhere was a secret-shaped-diff pattern match in a commit hook.
  Six security rules (`DR-01`…`DR-06`: untrusted input, authorization,
  secrets, external calls, uploads, data access) and five architecture rules
  (`DR-07`…`DR-11`: boundary violations, layer leaks, cycles, duplicated
  domain logic, responsibility creep) now read the code that actually got
  written, not the design that was approved before it existed. It is
  **conditional**: a 0-token shell prefilter greps the diff's paths and added
  lines for risk signals, and on the common no-signal run the agent is never
  spawned and the skip is logged with its reason. It is deliberately *not*
  tied to the size route — one low estimate must not be able to switch off
  the only security review in the plugin.
- **`debug-loop` leaves a record on disk**, written as the loop runs rather
  than assembled at the end — the run that most needs a record is the one
  that spends every attempt and stops, which is exactly the run with nobody
  left to summarize it. One file per failure, at
  `openspec/changes/<change>/_debug/<failure>.md` (or `.claude/debug/` for a
  direct invocation with no change in play), holding the failure and its
  reproduction, each attempt's hypothesis and its expected effect recorded
  *before* the fix, what actually happened, and the spec case above. A flake
  gets a record too, though no fix was attempted — until now the first phase
  named it and forgot it inside one conversation. On exhaustion the human is
  given the file's path, not only a retelling that dies with the session.
  The loop still writes no journal line and adds no journal field: counts in
  the journal, content in the record.

### Changed

- `architecture-review`'s "when invoked against a diff" mode is **removed**.
  It was written, was invoked by nothing, and duplicated what
  `deep-reviewer` now does on a schedule rather than on a manual call nobody
  made. Gate 1 reviews a proposed design; architecture in written code is
  `deep-reviewer`'s. There is no longer a second way to do the same thing.
- `test-plan` is invoked by `opsx-propose-review` after the gates pass, and
  re-run by `opsx-update-review` when a revision changes an acceptance
  criterion — a plan built against superseded wording is worse than none,
  since Gate 5 trusts it as the coverage floor.
- `.claude/harness.json` gains four keys, all picked up by upgrade mode:
  `disabledRules`, `sizeRouting`, `models.clarify` and `models.deep`.
  `models.deep` is seeded on a larger model than `models.code` precisely
  because it runs rarely.

## 0.4.1

A correctness fix in `dead-code-report`'s safety net, first automated
coverage for the scripts 0.4.0 added, and a progressive-disclosure pass over
the two largest instructions. Nothing in this release adds a manifest key or
changes a configured repository.

**That does not mean you can skip `/init-harness`.** 0.4.0 and 0.4.1 reach
users as one update, so a repository last configured under 0.3.0 still needs
the upgrade-mode run 0.4.0 describes below, to pick up `webQaScenariosDir`.
Only a repository already at 0.4.0 has nothing to do here.

### Fixed

- **`dead-code-report` could call a referenced file safe to delete.**
  `verify-string-reference.sh` excluded the candidate's own lines by
  filtering whole `grep` output lines on the candidate's path. A line in a
  *different* file that mentions that path — `"dynamicEntry":
  "src/formatPrice.ts"` in a build config, the exact reference the check
  exists to catch — contains the path too, so it was discarded along with
  the self-match and the script reported "nothing found". A file reachable
  only through a config string was therefore promoted into Group 1,
  "reliable / safe to delete". The exclusion now compares `grep`'s path
  field instead of the whole line, and handles a candidate passed as an
  absolute path (which previously failed to match itself at all).

### Added — tests

- `tests/dead-code-scripts.sh`: 10 checks over the five scripts 0.4.0
  added, which shipped with no automated coverage at all. Covers the
  string-reference safety net in both directions, generic-stem
  over-matching, `record-rejection`'s comment preservation / duplicate
  handling / JSONC validity, and `run-knip`'s unavailable-tool path.
- Three structural checks in `tests/smoke-json-schema.sh`: every
  `references/` and `scripts/` file must be reachable from its `SKILL.md`,
  every such path a `SKILL.md` names must exist, and every §-section
  citation (`§4 step 2`, `§5.3`) must resolve to a real section and step.
  An extracted file nobody points at is not documentation kept nearby — it
  is an instruction that silently stopped running, which is the one failure
  mode progressive disclosure introduces.
  The third check exists because the split itself caused that failure:
  moving §5's numbered steps out of `opsx-apply-git` left six citations
  across four files pointing at nothing, one of them inside the block
  written into the user's own `CLAUDE.md`. Those steps are back inline as a
  one-line-each outline — a numbered step other skills cite is a public
  anchor, not detail.

### Changed — instruction size

- `init-harness/SKILL.md` 838 → 408 lines and `opsx-apply-git/SKILL.md`
  475 → 433, by moving conditional and reference-shaped material into
  `references/`. A `SKILL.md` body loads in full every time its skill
  fires; a `references/` file loads only when an instruction says to read
  it. What moved is branch-specific (upgrade mode, the OpenSpec profile
  conversation, archiving, blocked-task handling) or lookup material (the
  manifest schema and field notes, the git-hook procedure, the CLAUDE.md
  block). What stayed inline is every step's existence, its trigger, and
  its stop condition — a run that never opens a reference still knows what
  it must do and when to halt.
- The grandfathered line ceilings in `tests/smoke-json-schema.sh` tightened
  to the new sizes in the same commit, so neither file can grow back into
  the space the split just freed.

## 0.4.0

The six review gates only ever look at what changed in the current task, so
anything that just sits in the project unreferenced was invisible to all of
them. This release gives the harness a way to see the whole project, not
just the diff, and adds the token/skip/outcome fields the journal needed to
answer any question about cost. No breaking change — `init-harness` in
upgrade mode picks up the one new manifest key on its own.

### Added — whole-project blind spots

- `code-reviewer`'s coverage criterion no longer treats a rising coverage
  percentage as reassurance when a diff is deletion-dominated — deleted code
  is by definition uncovered, so coverage always rises on that class of
  change regardless of whether the deletion was safe. The check now asks
  whether the removed code is actually unreferenced instead.
- `dead-code-report` skill: finds unused files, exports, and dependencies
  with `knip` plus the project's own lint rules, sorts findings into three
  confidence groups, and ends with a change-proposal draft — it never
  deletes anything itself. A string-reference safety net downgrades any
  "confident" finding still mentioned as a string anywhere in the project.
  Rejected findings are recorded in `knip.json` with a reason, so repeat
  runs get quieter instead of staying noisy forever. Not a gate; run
  manually, roughly monthly, alongside the existing review-ladder ritual.
- `web-qa` now offers to save each passed browser scenario as a real
  `@playwright/test` file, one at a time, under `.claude/harness.json`'s new
  `webQaScenariosDir`. Later Gate 3 runs replay the accumulated set first,
  at zero model cost, before the manual click pass covers what's actually
  new — closing the gap where a regression in an untouched surface went
  unnoticed until a user hit it.

### Added — plugin size discipline

- A per-`skills/*/SKILL.md` line-count ceiling, checked by
  `tests/smoke-json-schema.sh`. Today's two largest instructions
  (`init-harness`, `opsx-apply-git`) are grandfathered at their current
  length — nothing has to shrink today, but neither may grow further
  unnoticed.

### Added — measurability

- `tokensTotal` — combined token count per gate run, sourced from the
  environment's usage block, added to `.claude/harness-log.jsonl`.
- `skipReason` — closed four-value reason recorded on every skipped gate
  run, instead of a bare "skipped" that couldn't distinguish a healthy
  trivial-diff filter from a gate nobody uses.
- A new `kind: "finding"` log line, written once per CONFIRMED finding when
  `opsx-apply-git` forms a run's summary, recording which gate raised it and
  whether it was fixed, rejected, or deferred — closing the gap where a
  gate's verdict was never checked against what actually happened to it.
- `harness-stats` updated to read all three new fields; `kind: "finding"`
  lines are excluded from the existing per-gate run statistics so they don't
  deflate Gate 6's skipped-percentage denominator.

## 0.3.0

**Repositories `init-harness` already configured under 0.2.0 must run
`/init-harness` again, in upgrade mode, after updating this plugin.**
`/plugin update` only refreshes the plugin itself — its skills, agents, and
hooks; nothing in your repository changes until `/init-harness` runs there
again. This is the one breaking change in this release. See README's
"Keeping a configured repository in step with the plugin" for what upgrade
mode does and how it protects your existing customizations.

### Added — continuity across sessions

- `PROGRESS.md` and `docs/decisions/` ADRs, plus a `SessionStart` digest
  that now prints `PROGRESS.md`'s Status and Next steps, not just
  branch/status/recent commits — a new session's first read now answers
  what `git log -5` alone couldn't.
- `blocked` as a third `tasks.md` task state, alongside done/pending.
- Project-level WIP=1: `opsx-propose-review` refuses to start a new change
  while a previous one sits unarchived, naming it instead of silently
  proceeding.

### Added — bounded debug loop and recovery

- `debug-loop` skill: a bounded, four-phase fix loop (reproduce, isolate,
  diagnose, fix-and-reverify) that escalates to a human at `maxFixAttempts`
  instead of retrying forever — the one place in this harness where cost
  could previously run unbounded. Not a gate; doesn't block on its own.
- A plain-language run summary (3-5 sentences, what changed and why) now
  required in the run's PR body and chat output, not just a commit list.
- Definition of Done named explicitly as an ordered Static -> Runtime ->
  System contract, with "don't refactor before green" as a stated rule.

### Added — review quality

- Laziness ladder (`.claude/docs/laziness-ladder.md`): checked before
  writing new code, referenced from `code-reviewer`'s Simplification
  criterion and from `opsx-apply-git` before implementing a group.
- `code-reviewer` now also judges the observability of the application
  being built (PLAUSIBLE-only) — error handling that swallows context,
  critical paths with no log checkpoint.
- `reviewConfidence: high`/`low` added to all five review agents' Output —
  confidence in the review itself, separate from CONFIRMED/PLAUSIBLE on any
  individual finding; `low` never blocks on its own.
- A blocking dependency-vulnerability audit (`<pm> audit`/equivalent,
  high-or-above severity) chained onto `.husky/pre-push` after the coverage
  run.
- Requirement-ID (`FR-`/`NFR-`) traceability: a 0-token grep check surfaces
  an uncovered identifier by name before `code-reviewer` even runs, and
  reports "traceability unavailable" rather than a false "all covered" when
  a proposal defines no identifiers.
- Gate 6 (`harness-review`)'s CLAUDE.md hygiene check expanded into a
  Deletion Test with a knowledge-routing table.
- Gate 3 (`web-qa`) now requires a UI States Matrix per user-facing
  surface — loading/error/empty/offline, each with a verdict or an explicit
  "not applicable," never a silent skip.

### Added — measurability

- `fixIterations`, `escalatedToHuman`, and `reviewConfidence` fields added
  to every `.claude/harness-log.jsonl` line — all six gates and both of
  `opsx-apply-git`'s skip forms write the identical field set.
- `harness-stats` (`skills/harness-review/references/harness-stats.md`): a
  0-token shell+jq read over the log — verdict/duration distribution,
  fixIterations spread, escalation count, VCR, Rebuild Cost. No model call
  in this path.
- File-handoff: a run's diff over ~50 KB is written to a temp file and
  handed to `code-reviewer` by path instead of inlined as text.
- A monthly "harness diet" ritual, operationalizing this plugin's own
  ratchet principle: temporarily trim one gate or model, compare
  `harness-stats` before/after, keep the trim only on a real difference.

### Fixed — release blockers

- **Upgrade path.** `init-harness` now detects whether a repo was already
  configured by an earlier version (`.claude/harness.json`'s new
  `harnessVersion` key) and switches to upgrade mode: fill in what's
  missing, never silently overwrite a customized file. Gate 6 also checks
  for version drift independently.
- **Toolchain proof.** `init-harness` now actually *runs* the detected
  `typecheck`/`lint`/`test:coverage` scripts and confirms they pass — not
  just that the names exist in `package.json` — before writing
  `toolchainVerifiedAt` and `harnessVersion`. A renamed script now fails
  setup instead of silently shipping a dead `.husky/pre-commit`.
- `init-harness` seeds `openspec/config.yaml` with the project's detected
  context and artifact rules; the file is now in Gate 6's drift-check scope.

### Tests and docs

- `tests/hook-behaviour.sh` and `tests/smoke-json-schema.sh` extended to
  cover every new surface above: `SessionStart`'s three `PROGRESS.md`
  states, the new manifest keys' shape, identical `harness-log.jsonl` field
  sets across all eight write sites, and `debug-loop`'s frontmatter.
- `tests/MANUAL-CHECKLIST.md` gained an upgrade-from-0.2.0 scenario (a real
  0.2.0 checkout, `/plugin update`, `/init-harness` in upgrade mode), a
  `maxFixAttempts`-exhaustion scenario, and a blocking-pre-push-audit
  scenario.
- README brought current with this release end to end: the new "Upgrading
  from 0.2.0" section, a corrected skill count, `init-harness`'s full file
  inventory, the `debug-loop` row, and `reviewConfidence`.

## 0.2.0

The plugin's first working release. 0.1.0 shipped several defects that made
it not do what its own README described; a nine-session audit found and
fixed them. Anyone still on 0.1.0 should update.

### Fixed — gates that silently did nothing

- **Gate 3 ran without a browser.** `web-qa-manual-tester` listed its
  Playwright tools as `mcp__playwright__*`, but a plugin-bundled MCP server
  exposes `mcp__plugin_<plugin>_<server>__<tool>`. No name matched, so the
  agent launched with `Read`/`Grep`/`Glob` only and reported on the source
  instead of the running UI — with no error.
- **Every agent loaded with empty metadata.** An unquoted `description`
  containing `<example>Context: ...` broke the YAML frontmatter, so `name`,
  `description`, `tools` and `model` were all dropped. `tools:` is what
  makes these agents read-only.
- **The hook layer never loaded** (`hooks/hooks.json` was missing its
  top-level `hooks` wrapper), and **`spec-reviewer` had no `Edit` tool**, so
  the isolated/judgement-heavy classification never reached `tasks.md`.
- **OpenSpec was installed from the wrong package** — `openspec` on npm is
  an empty squatter; the real CLI is `@fission-ai/openspec`.

### Fixed — hooks

- The typecheck `Stop` hook ignored `stop_hook_active` and re-blocked every
  stop, up to Claude Code's 8-block cap, on any type error the model
  couldn't fix.
- Its `npx tsc` fallback ran npm's deprecated `tsc` stub package rather than
  the compiler, then reported that stub's output as a type error. The hook
  now resolves the manifest command, then `node_modules/.bin/tsc`, then
  skips.
- Both project-file hooks resolved paths relative to the session's working
  directory, so a session opened in a subdirectory silently disabled
  `.claudeignore` enforcement and the typecheck. They anchor to
  `${CLAUDE_PROJECT_DIR}` now.
- The push guard read `$ARGUMENTS`, which is empty in a command hook, so its
  force-push check never fired. Guards also stopped assuming `main`/`master`
  and now read `origin/HEAD`, and handle detached HEAD.
- The agentic commit gate became a deterministic shell hook: no model call
  per commit.

### Fixed — permissions

- The install-command deny list missed `npm add`, `pnpm install`, `pnpm i`
  and every `bun` spelling, so a block on `yarn add` was routable.
- `Write(path)` rules are accepted by Claude Code but never consulted; the
  template now writes `Edit(path)`, which covers every file-editing tool.
- Dropped an unprompted write grant to `./.claude/skills/**` — a leftover
  from the pre-plugin layout, and a silent channel into files loaded as
  instructions in later sessions.
- Removed `node -e` / `node -p` / `cat` / bare `Write`/`Edit` from the allow
  list, added the git subcommands the workflow actually needs.

### Changed

- Gate 4 and Gate 5 merged into one `code-review` delegation over the same
  diff; review depth follows the isolated/judgement-heavy classification;
  Gate 6 and the whole review pass are skipped for trivial diffs by 0-token
  shell pre-filters. Roughly a 70% cut in agent spawns per change.
- Per-gate model tiers, configured in `.claude/harness.json` rather than
  agent frontmatter.
- `init-harness` writes `.claude/harness.json` as the single stack manifest
  every skill and hook reads, plus a pointer block in `CLAUDE.md`/`AGENTS.md`
  so the harness docs are discoverable at all.
- `init-harness` now gates on OpenSpec's *workflow list* (`new`, `continue`,
  `verify`), not its `profile` string: a `custom` profile can be missing
  exactly those.
- Husky split into a fast `pre-commit` (typecheck + lint + lint-staged) and
  a full `pre-push` (coverage).
- Removed the `sequential-thinking` MCP server; pinned
  `@playwright/mcp@0.0.78`.

### Added

- `tests/smoke-json-schema.sh` — manifest shapes, frontmatter parseability,
  and `claude plugin validate --strict` when the CLI is available.
- `tests/hook-behaviour.sh` — 23 checks driving every hook against a
  throwaway git repo.
- `tests/fixtures/` — vite-vitest-yarn and next-jest-pnpm regression
  fixtures, and `tests/MANUAL-CHECKLIST.md`.

## 0.1.0

Initial extraction of the harness into plugin form. See 0.2.0 for the
defects this release shipped with.
