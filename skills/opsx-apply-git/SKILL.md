---
name: opsx-apply-git
description: Implements the next run from an OpenSpec change — an autonomous batch of consecutive isolated task groups, or a single judgement-heavy group with a human in the loop — inside a branch-per-group git workflow with the project's review gates, auto-committing each group when green, opening one PR per run into the parent branch, and auto-archiving via its own PR once that run's PR has merged. Use instead of the vendored openspec-apply-change whenever the user wants to implement, continue, or work through OpenSpec tasks.
---

Implement the next run from an OpenSpec change inside this project's git
workflow and review gates — not just checking task boxes.

**One run per invocation.** A "run" is either an autonomous batch of
consecutive `isolated` groups or a single `judgement-heavy` group. Work the
run to completion, then stop and report — do not start the next run in the
same session. If the run finished the last pending group, continue straight
into archiving (step 5) instead of stopping at the report — but step 5
itself may need to stop and wait there for a human to merge the run's PR
first (see below).

## 0. Read the harness docs first

Read `.claude/docs/git-conventions.md` and `.claude/docs/review-gates.md` in
the target repo (written by `init-harness`) before touching any code — they
are the source of truth for branch naming, commit format, and gate order.
Then **read `references/command-hygiene.md`**, before the first Bash call;
read `references/ci-probes.md` before any task that must push failing code.

## 1. Determine the parent branch and read the stack manifest

1. `git branch --show-current` — this should be the parent feature branch
   already active, never `main`/`master`. If it looks like a leftover group
   branch (a batch, group or archive branch this skill cut earlier), check
   its PR before asking anything. `.claude/harness.json`'s `forge` is
   `"github"` or absent → `gh pr view --json state,baseRefName` on it:
   - `MERGED` → `git checkout <baseRefName>` — that is the parent — and
     report it in one line: `Branch <group> is merged into <baseRefName>;
     switched to <baseRefName>.` Then go on: a change with no pending tasks
     left goes to §5 with this PR as the run's PR.
   - Any other state, no PR for the branch, or `forge` `"other"` → stop and
     ask which branch is the real parent.
   Switch only on `MERGED`: the PR's own base is the one fact that says where
   the group's work went, and a guess would send the next run to the wrong
   branch.
2. Read `.claude/harness.json` (written by `init-harness`) for
   `packageManager`, `runCmd`, `framework`, `testRunner`, `buildDir`,
   `scripts`, `devServerUrl`, and `coverageThreshold` — every verification
   command below depends on these, not on assuming `yarn`/Vite. Do not
   re-detect the stack from lockfiles or config files. If the manifest is
   missing, stop and tell the user to run `init-harness` first — see
   `${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/stack-detection.md`
   for what it detects and why this skill doesn't duplicate that logic.

## 2. Standard OpenSpec selection and context

1. Select the change (explicit name, inferred, or ask via `AskUserQuestion`).
2. `openspec status --change "<name>" --json` for schema and progress.
3. `openspec instructions apply --change "<name>" --json` for context files
   and the task list.
4. Read only the slice of `contextFiles` this run actually needs, not the
   whole set on every invocation (cost-optimization #42) — a long change
   re-reading its full proposal/design/every capability's spec on every
   single run, when a given run only ever touches one or two groups, spends
   context on files that aren't relevant to what this run is about to do:
   - `tasks.md` itself — always; §3 depends on it to determine groups, read
     the isolated/judgement-heavy marks, and read any `blocked` task marks.
   - `proposal.md` / `design.md` — only on this change's very first run (no
     group anywhere in `tasks.md` is committed yet), or later if a group's own ambiguity genuinely requires re-checking the original intent — not by default on every subsequent run of an already-in-progress change.
   - The spec file(s) under `contextFiles` that cover the group(s) this run
     is about to implement (§3 determines which) — not the full spec set for
     a change that spans capabilities this run isn't touching.
   - Anything else under `contextFiles` — read on demand only if a specific
     question comes up mid-run, not upfront.
   - `ui-plan.md`, before writing component code — **read `references/ui-plan-read.md` now and follow it.**

## 3. Work the next run: isolated batch, or one judgement-heavy group

A "group" is a numbered `##` heading in `tasks.md`, not a sub-task. Read the
`<!-- isolated -->` / `<!-- judgement-heavy -->` marks `spec-review` wrote.
**An unmarked group counts as judgement-heavy** — never auto-run an
unclassified group.

### Requirement-ID markers

If a task names the `FR-`/`NFR-` identifier it implements (`rules.tasks` in
`openspec/config.yaml`, seeded by `init-harness` Step 2f, requires this),
leave a matching `implements <ID> of <change-name>` comment — any comment
syntax works, `//`, `/* */`, JSDoc, a docstring — in the code or test that
actually satisfies it, while working the task below. This is the only thing
`code-review`'s grep-based coverage check (§4 step 2;
`skills/code-review/SKILL.md`) has to go on: skip the comment and the
identifier reports as uncovered even though the work happened.

### Blocked tasks

A task can carry a third, independent marker: `<!-- blocked: <reason> -->`,
written on the task's own `- [ ]` line — never on the group's `##` heading.
This skill writes it at the moment a run stops without resolving the task
(Case A step 5's pause, or Case B step 2's pause that outlives the run);
`spec-review` never does.

Two rules bind every run's scan, so they stay here rather than in the
reference:

- **A group containing any blocked task is never eligible for Case A's
  autonomous batch**, whatever its own classification says. Skip past it when
  scanning for the next run's starting point, and if every remaining group is
  blocked, stop and report rather than inventing work.
- **Clearing a block is never automatic** — no timeout, no retry-and-forget.

When about to write a marker, or when a scan finds one, **read
`references/blocked-tasks.md` and follow it** — it covers the standalone
commit the marker gets, why a block holds back the whole group, and what Case
B may still do deliberately. Before any commit that leaves a task blocked,
skipped or obsolete, or ticks one with a `deferred` pointer, **read `references/deferred-log.md`**.

### Syncing the parent (used by both cases below)

`git fetch origin && git pull --ff-only` (skip entirely if the parent has no
upstream yet) is the happy path. It fails as soon as a previous run's PR was
merged with squash or rebase — common defaults on many repos — because the
parent's local history no longer has a commit that's an ancestor of
`origin/<parent>`, so a fast-forward is impossible even though nothing was
actually lost. Don't treat that failure as a hard stop without checking which
case it is:

1. Run `git fetch origin`, then `git pull --ff-only`.
2. On failure, check **both** directions before concluding anything:
   `git log --oneline <parent>..origin/<parent>` (what's new upstream) *and*
   `git log --oneline origin/<parent>..<parent>` (what's local-only, not on
   `origin` at all). The squash/rebase-merge case is specifically: the first
   command shows a single squashed commit (or rebased sequence) that
   supersedes exactly what this branch already had, **and** the second
   command is empty — no local-only commits exist for `reset --hard` to
   discard. If the second command shows anything, this isn't the safe case:
   there's un-pushed local work that `reset --hard` would destroy, even if
   the first command also looks like a clean squash.
3. Only when the local-only side is empty, propose `git reset --hard
   origin/<parent>` to the user and get **explicit confirmation** before
   running it. This is the one documented, narrowly-scoped exception to this
   skill's rule against destructive/history-rewriting operations (see
   Exceptions below) — it's safe here only because the squashed/rebased
   commit already contains everything the local branch had and nothing
   local-only would be lost, and it must never run without that
   confirmation (#18).
4. If the divergence doesn't match that exact shape — local-only commits
   exist, the upstream side doesn't look like a clean squash/rebase, or
   anything else is ambiguous — stop and ask. Don't guess at a merge, rebase,
   or reset yourself.

### Case A — first pending group is isolated: autonomous batch

1. Sync the parent (see above), cut one batch branch off it
   (`<type>/<change>-isolated`, per git-conventions.md naming).
2. For each isolated group in turn: weigh what to build against
   `.claude/docs/laziness-ladder.md`, and check `references/context7-lookup.md`'s
   trigger against the task's own text and acceptance criteria, before writing
   anything new (a named library or framework API → context7 first, per that
   file). On `makerChecker.enabled`, follow `references/maker-checker.md`
   first: this group's tests are written by another actor, before its code. A
   new service boundary with `tests.integration` set → `references/integration-tests.md`.
   Then implement its sub-tasks (minimal, focused; mark `- [ ]` → `- [x]`). A decision the
   agent can't confidently make means the classification was wrong — stop,
   leave it uncommitted, tell the user. One it CAN make confidently: read
   `references/decision-threshold.md` — it may still need recording (Proposed)
   without stopping the group.
3. Once green (its own verification + lint), confirm scope (`git status -s`,
   `git diff --stat` — no unrelated files) and commit the group's own
   implementation immediately (Conventional Commits, per
   git-conventions.md). `code-review` (Gate 4+5) no longer runs per group
   for an isolated batch — trusting the classification enough to run a
   group unattended but not to review it as part of a batch pass would be
   inconsistent, so it runs once against the whole batch's cumulative diff
   instead, after the last group (§4 step 2; cost-optimization #34). On the
   *last* group **with pending tasks in the whole change** (not just the
   last group of this batch — a batch can end mid-change, handing off to a
   judgement-heavy group next) — run Gate 3 (`web-qa`) first if the change
   touched user-facing UI — must-pass with a fix loop, its fixes folding
   into that group's diff before the commit.
4. Next pending group: isolated → continue the loop; judgement-heavy or none
   left → end the batch, go to §4.
5. Any pause during implementation (an error, an ambiguity, a design
   decision the agent can't confidently make — step 2's other kind, the one
   it CAN make, never pauses here) stops the batch where it is — report and
   wait, never commit a half-finished group. Write `<!-- blocked: <reason>
   -->` on the specific task line that caused the stop and commit that
   one-line edit on
   its own (see §3's Blocked tasks section) — the task itself stays
   uncommitted and unchecked; only the marker is committed. A CONFIRMED finding from the batch-level
   `code-review` pass in §4 can only surface once every group in the batch
   is already committed; its fix lands as a new commit appended to the
   batch, never an amend of an earlier group's own commit.

### Case B — first pending group is judgement-heavy: one group, human in the loop

1. Sync the parent (see above), cut a single group branch off it, named for
   the group.
2. Announce why it's judgement-heavy. Weigh what to build against
   `.claude/docs/laziness-ladder.md`, and check `references/context7-lookup.md`'s
   trigger the same way Case A's step 2 does, plus `references/maker-checker.md`
   and `references/integration-tests.md` when they apply, before writing anything new. Then implement with the standard guardrails, but
   pause and ask on every design decision or ambiguity. If the run ends
   (report and stop, §4 step 7) before that question is answered, write
   `<!-- blocked: <reason> -->` on the specific task line waiting on it and
   commit that one-line edit on its own (see §3's Blocked tasks section) —
   an ordinary pause answered within the same turn never touches
   `tasks.md`; only one that outlives the run does. A decision reached this
   way was already discussed live, so if it crosses
   `references/decision-threshold.md`'s bar, record it straight as Accepted
   (never Proposed) — that file has the bar and the routing rule.
3. Once green, confirm scope and — if this is also the *last* group with
   pending tasks in the whole change and it touched user-facing UI — run
   Gate 3 (`web-qa`) first, its fixes folding into the diff. Commit the
   group's own implementation, then go to §4 — a judgement-heavy run is a
   single group, so `code-review`'s batch-level pass in §4 step 2 is
   already reviewing this one commit's whole diff, the same as it would for
   an isolated batch of one.

## 4. Review the run, push + PR

Every group in this run is already committed by §3 (implementation commits
happen inline, per group) — every step below runs once per run, not once
per group; that's the whole point of #34: an isolated batch trusted to
implement unattended is reviewed as one unit too, not group-by-group.

1. **Trivial-diff pre-filter (0 tokens)** — before spawning `code-review` at
   all, check the run's cumulative diff (`git diff <parent>..HEAD`, the same
   diff step 2 below would review) against `.claude/harness.json`'s
   `trivialDiffThreshold` / `trivialDiffPaths` (seeded by `init-harness`).
   Read them explicitly — don't assume the seeded defaults are still what's
   in the manifest — and fail closed to those same defaults (10 changed
   lines / `*.md`, `*.css`, `*.svg`, `public/**`) if either key is missing
   or the manifest can't be parsed, rather than guessing or skipping the
   check entirely:
   ```bash
   threshold=$(jq -r '.trivialDiffThreshold // 10' .claude/harness.json 2>/dev/null)
   [ -n "$threshold" ] || threshold=10
   globs=$(jq -r '.trivialDiffPaths[]? // empty' .claude/harness.json 2>/dev/null)
   [ -n "$globs" ] || globs='*.md
   *.css
   *.svg
   public/**'
   stat=$(git diff --shortstat <parent>..HEAD)
   ins=$(printf '%s' "$stat" | grep -oE '[0-9]+ insertion' | grep -oE '[0-9]+')
   del=$(printf '%s' "$stat" | grep -oE '[0-9]+ deletion' | grep -oE '[0-9]+')
   lines=$(( ${ins:-0} + ${del:-0} ))
   ```
   (python3/node fallback if `jq` isn't available, same pattern as this
   project's hooks.) If `lines` is under `threshold` **and** every path from
   `git diff --name-only <parent>..HEAD` matches one of the `$globs` lines
   (loop each changed file through a `case "$f" in $g) ... esac` against
   each glob line — a single path outside the trivial set disqualifies the
   whole run), skip the `code-review` delegation entirely
   (cost-optimization #36): a 3-line CSS tweak or a typo fix in a `.md` file
   doesn't need a full review pass. This must stay a deterministic shell
   check — never "ask the model if this looks trivial," which would spend
   exactly the tokens this step exists to avoid. When skipped, write all
   three log lines yourself (same shape `code-review` would write, all
   `verdict:"skipped"`) — nobody else writes `deep-review`'s line either:
   ```bash
   mkdir -p .claude/harness-log
   for g in code-review test-coverage deep-review; do
     printf '%s\n' "$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
       --arg change "<change-slug>" --arg group "<group-number-or-range>" \
       --arg gate "$g" \
       '{ts:$ts,change:$change,group:$group,gate:$gate,verdict:"skipped",skipReason:"small change",durationMs:0,tokensTotal:0,tokensNote:"",model:"",reviewConfidence:"",fixIterations:0,escalatedToHuman:false}')" \
       >> ".claude/harness-log/$(git branch --show-current | sed "s#/#--#g").jsonl"
   done
   ```
   Then skip straight to step 3 (Gate 6's own precondition, #35 — evaluated
   independently, since even a trivial-by-this-filter diff can still touch
   harness config worth flagging). Otherwise, continue to step 2.
2. Run **`code-review`** — Gate 4 and Gate 5 in one delegation (merged per
   cost-optimization #33, since they always reviewed the same diff back to
   back) — against:
   - **Case A (isolated batch)** — the batch's cumulative diff,
     `git diff <parent>..HEAD`, covering every group's commit in this batch
     in one pass.
   - **Case B (judgement-heavy)** — the single group's diff against the
     parent (the run *is* one group, so this is already the whole run).
   Check that diff's size before handing it to `code-review`:
   ```bash
   diff_size=$(git diff <parent>..HEAD | wc -c)
   diff_file=""
   if [ "$diff_size" -gt 51200 ]; then
     diff_file=$(mktemp)   # in $TMPDIR, outside the repo: `git add .` can't pick it up
     git diff <parent>..HEAD > "$diff_file"
   fi
   ```
   Under ~50 KB (`diff_file` empty), pass the diff text inline in the
   delegation as before. Over ~50 KB, pass `code-reviewer` `$diff_file`'s
   *path* plus the `<parent>..HEAD` revision range instead of the text
   itself — `code-reviewer` has both `Read` and `Bash`, so it reads the file
   or re-runs the `git diff` itself. This threshold rarely fires in practice
   (`isolated` groups are small by construction, and a run is at most five
   of them), but the one diff this controller does hold onto for a whole
   run — the batch's cumulative diff — is also the one genuinely large text
   it passes anywhere. **Whenever `diff_file` was set**, `rm -f "$diff_file"`
   before this step is considered done, on every exit path — the CONFIRMED
   fix-and-continue path below, the clean/PLAUSIBLE continue path, and the
   `maxFixAttempts`-exhausted stop path (a stopped run still ends this step;
   it doesn't get to skip cleanup because it stopped early). Subagent
   reports stay inline either way — short lists, needed at once to decide
   pause-or-continue; a file would add a round-trip for nothing.
   Skip the Gate 5 section only if that cumulative diff is docs/config-only
   (no source or test files touched anywhere in the run) — a run that
   shipped source changes with no tests anywhere in it is exactly what that
   section exists to catch. CONFIRMED in either section → pause and ask
   fix-now-or-continue; "fix now" runs through the `debug-loop` skill,
   bounded by `.claude/harness.json`'s `maxFixAttempts`, rather than a single
   ad hoc edit. A resulting fix lands as its own new commit appended to the
   run's branch, never an amend of an already-committed group. Since later
   groups in the same batch may have built on top of the flawed one, re-run
   the project's own verification (typecheck/lint/tests) after applying the
   fix, before pushing — don't assume a fix scoped to the group that
   introduced the problem is automatically compatible with what later
   groups added on top of it. If `debug-loop` exhausts `maxFixAttempts`
   instead of resolving the finding, this is report-only — every group in
   the run is already committed by this point, so there's no open task line
   to write a `blocked` marker on (unlike §3 step 5's pause, which is mid-
   implementation). Stop this run, leave the branch as is, and report every
   attempt's hypothesis to the human — don't push past it (`rm -f
   "$diff_file"` first, per above). Clean/PLAUSIBLE in
   every section → continue. Separately from that verdict, `code-reviewer` —
   and `deep-reviewer` whenever the prefilter spawned it — each report their
   own `reviewConfidence`. On **Case A (isolated batch)**, a run with no
   CONFIRMED finding but `reviewConfidence: low` from *either* continues —
   this does not block — but show the human the reason before pushing (step
   4 below): a batch trusted enough to implement unattended got a clean
   verdict the reviewer itself wasn't fully confident in, and that is worth
   seeing even though it isn't worth stopping for. On **Case B
   (judgement-heavy)**, the human is already in the loop for this run, so
   `reviewConfidence: low` needs no separate surfacing here — it will be
   visible in the same report they're already reading.
3. **Gate 6 precondition (0 tokens), then `harness-review` if it applies** —
   on this run's last group with pending tasks only, before spawning
   `harness-reviewer` at all, check whether this run touched anything it
   could plausibly review:
   `git diff --name-only <parent>..HEAD | grep -qE '^(CLAUDE|AGENTS)\.md|^\.claude/|^\.husky/|^openspec/config\.yaml$'`,
   or `package.json`'s `scripts`/`dependencies`/`devDependencies`/
   `peerDependencies` actually changed. Compare those keys structurally, not
   with a line-based diff grep — a line-based check either misses a
   single-line/minified `package.json` or false-fires on an unrelated
   change (a `version`/`description` bump) whose diff hunk merely happens to
   include a `"scripts"` line as context:
   ```bash
   old_pkg=$(git show <parent>:package.json 2>/dev/null | jq -cS '{scripts,dependencies,devDependencies,peerDependencies}' 2>/dev/null)
   new_pkg=$(jq -cS '{scripts,dependencies,devDependencies,peerDependencies}' package.json 2>/dev/null)
   [ "$old_pkg" != "$new_pkg" ] && pkg_changed=true
   ```
   (python3/node equivalents if `jq` isn't available, same fallback pattern
   as this project's hooks.) Most runs touch neither — a run that never
   touched the harness has nothing for this gate to find. In that case,
   skip the `harness-review` delegation
   entirely and append the skip directly to this branch's log file, `.claude/harness-log/<branch>.jsonl`
   yourself (create the file if it doesn't exist), since the skill that
   normally writes that line never ran:
   ```bash
   mkdir -p .claude/harness-log
   printf '%s\n' "$(jq -nc --arg ts "$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
     --arg change "<change-slug>" --arg gate "harness-review" \
     '{ts:$ts,change:$change,group:"-",gate:$gate,verdict:"skipped",skipReason:"harness config unchanged",durationMs:0,tokensTotal:0,tokensNote:"",model:"",reviewConfidence:"",fixIterations:0,escalatedToHuman:false}')" \
     >> ".claude/harness-log/$(git branch --show-current | sed "s#/#--#g").jsonl"
   ```
   If `jq` isn't available, construct the equivalent line with `printf`
   instead, matching `harness-review`'s own log format. If either
   precondition check matches, run **`harness-review`** (Gate 6) as before —
   it writes its own log line per its skill doc. On an approved finding,
   apply the fix and
   commit it separately — never `git commit -a`/`-am`. Stage **exactly the
   files the fix touched** with explicit paths (`git add
   <the-touched-file(s)>`), never a directory shorthand like `.claude/`
   that could also pick up unrelated changes. Gate 6's scope bounds where
   those files can come from — `CLAUDE.md`/`AGENTS.md`,
   `.claude/harness.json`, `.claude/settings.json`, `.claude/docs/**`,
   `.husky/**`, `openspec/config.yaml`, plus this plugin's own
   `skills/`/`agents/` when its own repo is what's under review — e.g.
   `git add .husky/pre-commit && git commit -m "chore: harness review — <summary>"`.
   Every group is already committed (§3): it lands as the next commit.
3a. **Replay the recorded scenarios — read `references/e2e-replay.md` now and
   follow it.** Otherwise only the next `web-qa` runs them, and a change
   with no interface never does.
4. If step 2 flagged a Case A run with `reviewConfidence: low` and no
   CONFIRMED finding, print the reviewer's stated reason to the chat now
   (step 2 deferred it here). Then push the run's branch (`git push -u
   origin <branch>`, on its own: never piped, see `references/command-hygiene.md`)
   — **read `references/pre-push-note.md` before it**: the integration tests' log line.
5. Ensure the parent branch exists on `origin` (push it first if local-only).
6. Write the run's summary and this run's review trail, then open the PR. **Read `references/log-findings.md` now and follow it** — it covers logging CONFIRMED findings, composing the "Review trail" section named in step 3 below, and committing the log folder `.claude/harness-log/` per step 2 below.
   1. Compose a **"What changed and why"** section: 3-5 sentences of plain
      language covering what this run actually did and why, in terms a
      human who hasn't read the diff can follow. This is *not* satisfied by
      a list of commit subjects, `git diff --stat` output, or "all gates
      green" — none of those three describe the change, they describe
      process, and the point of this section is to force the run to be
      stated in words, which is only possible once it's actually
      understood.
   2. Commit and push `.claude/harness-log/` (per `log-findings.md`),
      then print both sections — before step 6.3 opens or prints the PR, the
      one point in an autonomous batch where a human sees the run in prose
      instead of tool output, with a chance to intervene.
   3. `.claude/harness.json`'s `forge` key decides how this run's PR opens —
      absent (a manifest written before 0.6.0) behaves the same as
      `"github"`, unchanged. `"github"` → open one PR from the run's branch
      into the parent (`gh pr create`). `"other"` → skip `gh` entirely and
      print the branch name, the parent branch it targets, and the composed
      PR body instead, so the human opens the PR by hand in under a minute.
      Either way, cover every group in this run, with the PR body
      **starting** with "What changed and why" and "Review trail" right
      after it. **Judgement-heavy run** → the existing
      `⚠️ Judgement-heavy: needs careful human review` marker still leads the
      body, ahead of both sections. Leave the PR open — the human owns the
      merge.
7. **Tasks remain** → clock out in `PROGRESS.md` with the script, never by
   hand (`${CLAUDE_PLUGIN_ROOT}/skills/init-harness/references/progress-template.md`):
   ```bash
   node "${CLAUDE_PLUGIN_ROOT}/skills/opsx-apply-git/scripts/progress.mjs" clock-out \
     --change "<change-slug>" --branch "<this run's branch>" \
     --last-commit "<short-hash> — <subject>" --done "<groups done, or none>" \
     --in-progress "<group, or none>" --blocked "<group/task — reason, or none>" \
     --next "<step>" --next "<step>" \
     --clock-in "<this session's start, ISO-8601 UTC>" --clock-out "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
   ```
   One `--next` per remaining step; the script numbers them and drops this
   change's `## Paused changes` line. Blocked reason = the task's
   `<!-- blocked: ... -->` marker. Re-read the file against `tasks.md`; on a
   mismatch, rerun with corrected values. Never commit it: it is gitignored.
   Report progress and stop, calling out any blocked task by name and reason
   as its own line in the report rather than folding it into the general
   summary — the next `opsx-apply-git` invocation re-syncs the parent from
   `origin` (only picks up this run's work once its PR is merged). **No
   tasks remain** → continue to §5.

## 5. Auto-archive once the run's own PR has merged

Only on a run that leaves no pending tasks in the change. Archiving mutates
the parent's `openspec/changes/` tree, so it waits on this run's own PR being
**merged** — archiving a change whose PR was later rejected would record an
acceptance that never happened (#19).

**Read `references/archive-run.md` now and follow it.** Its steps are
numbered as below; other skills cite these numbers, so they stay listed here:

1. **Check the run's PR state.** `.claude/harness.json`'s `forge` is
   `"other"` → ask the human directly whether this run's PR has merged.
   Anything else (`"github"`, or absent) → `gh pr view <branch-or-number>
   --json state --jq .state`. Either source resolves to the same three
   outcomes, not two: `MERGED` → sync the parent and cut the archive branch
   off its now-current tip. `OPEN` (or the human says not yet) → stop and
   report; archiving waits on the human's merge. `CLOSED` and not merged (or
   the human says it was rejected) → stop and ask, the merge isn't coming.
2. Run `openspec archive <change-name>`, then `deferred-log.md`'s write 3.
3. **Commit the archive move** (`chore: archive <change-name>`) — the second,
   narrower override of "never commit without being asked", same
   justification as §3's per-group commit override.
4. Push the archive branch. Same `forge` branch as step 6.3 above: `"other"`
   → print the archive branch name and the parent branch instead of a PR
   call; otherwise open a PR into the parent (`gh pr create`). Leave it open.
5. **Clock out in `PROGRESS.md` one final time** for this change, with the
   same script call as §4 step 7 (`--change none`, no `--next`). It is
   gitignored, so there is nothing to commit. Then report the full session.

## Exceptions

- An unrelated fix found mid-task can land as its own focused commit.
- Destructive/history-rewriting git operations are never part of this flow
  — stop and ask if something goes wrong. The **only** exception is the
  confirmed `git reset --hard origin/<parent>` in the squash/rebase-merge
  recovery above (§3), and only under the exact narrow conditions and
  explicit human confirmation described there — it is not a general license
  to reset, and nothing else in this flow rewrites history or discards
  commits.
