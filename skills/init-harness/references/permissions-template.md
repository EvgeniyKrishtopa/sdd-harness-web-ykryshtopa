# Permissions template (merge into `.claude/settings.json`)

`init-harness` merges this into the target repo's `.claude/settings.json`
under the top-level `"permissions"` key, as a **sibling** of `"hooks"` — not
inside it. Never overwrite an existing `permissions` block wholesale; merge
array entries, de-duplicating.

Substitute `{{PACKAGE_MANAGER}}` with the detected command (`yarn`/`npm run`/
`pnpm`), `{{BUILD_DIR}}` with `dist` (Vite) or `.next` (Next.js), and
`{{LOCKFILE}}` with the detected lockfile (`yarn.lock`/`package-lock.json`/
`pnpm-lock.yaml`). Do not leave literal placeholders in the written file.

```json
{
  "permissions": {
    "allow": [
      "Bash({{PACKAGE_MANAGER}} typecheck:*)",
      "Bash({{PACKAGE_MANAGER}} lint:*)",
      "Bash({{PACKAGE_MANAGER}} dev:*)",
      "Bash({{PACKAGE_MANAGER}} build:*)",
      "Bash({{PACKAGE_MANAGER}} preview:*)",
      "Bash({{PACKAGE_MANAGER}} test:*)",
      "Bash({{PACKAGE_MANAGER}} test:run:*)",
      "Bash({{PACKAGE_MANAGER}} test:coverage:*)",
      "Bash(npm info *)",
      "Bash(npx openspec:*)",
      "Bash(openspec:*)",
      "Bash(pkill -f:*)",
      "Bash(cd:*)",
      "Bash(curl -s http://localhost:*)",
      "Bash(which:*)",
      "Bash(mkdir:*)",
      "Bash(echo:*)",
      "Bash(sleep:*)",
      "Bash(kill:*)",
      "Bash(git commit -m *)",
      "Bash(git checkout *)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git fetch:*)",
      "Bash(git pull --ff-only:*)",
      "Bash(git ls-remote:*)",
      "Bash(git add:*)",
      "Bash(git push:*)",
      "Bash(git branch:*)",
      "Bash(git rev-parse:*)",
      "Bash(git log:*)",
      "Bash(gh pr create:*)",
      "Write(./.claude/docs/**)",
      "Edit(./.claude/docs/**)",
      "Write(./.claude/harness.json)",
      "Edit(./.claude/harness.json)"
    ],
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Bash(cat .env:*)",
      "Bash(rm -rf:*)",
      "Bash(rm -fr:*)",
      "Bash(rm -r -f:*)",
      "Bash(find . -delete:*)",
      "Bash(git clean:*)",
      "Bash(git reset --hard:*)",
      "Bash(npm install:*)",
      "Bash(npm i:*)",
      "Bash(npm add:*)",
      "Bash(pnpm add:*)",
      "Bash(pnpm install:*)",
      "Bash(pnpm i:*)",
      "Bash(yarn add:*)",
      "Bash(bun add:*)",
      "Bash(bun install:*)",
      "Bash(bun i:*)",
      "Bash(screencapture:*)",
      "Read(./node_modules/**)",
      "Read(./{{BUILD_DIR}}/**)",
      "Read(./coverage/**)",
      "Read(./{{LOCKFILE}})",
      "Read(./.env)",
      "Read(./.env.*)"
    ]
  }
}
```

## Notes on generalization from the original project

- The source repo (Vite, yarn-only) denied `Read(./yarn.lock)` specifically.
  Here it's whichever lockfile `init-harness` detected — always deny reading
  the lockfile, not just the yarn one, since it's large and rarely relevant
  to a task.
- Every package manager's dependency-adding command stays in `deny`
  **regardless of which one this project actually uses** (defense in depth —
  an agent can't route around the install-command block by invoking a
  different package manager than the one detected). "Every" has to mean
  every *spelling*, not one entry per tool: `npm add` is an alias of
  `npm install`, `pnpm install <pkg>` and `pnpm i <pkg>` add a package just
  like `pnpm add` does, and `bun` is a fourth package manager an agent can
  reach for even in a repo that has never used it. A list that blocks
  `npm install` but not `npm add` isn't defense in depth; it's a speed bump
  with a marked detour.
- One asymmetry is deliberate and worth knowing about: `yarn install`
  (restore from lockfile) stays allowed because yarn can't add a package
  that way, while `npm install` / `pnpm install` are denied even though
  they're also the restore spelling for those tools — there, the same
  command does both jobs, and blocking dependency changes wins over
  convenience. If a restore is genuinely needed, run it yourself in a
  terminal.
- `Bash(npx openspec:*)` / `Bash(openspec:*)` match the CLI **binary** name,
  which is `openspec` regardless of package name. The npm package installed
  in Step 2 is `@fission-ai/openspec` (the bare `openspec` package is an
  unrelated empty squatter) — that only affects the install command, not
  these permission entries.
- `{{BUILD_DIR}}` is `dist` for Vite, `.next` for Next.js — read the detected
  framework from Step 1, don't hardcode one.
- This `permissions.deny` list is only as strong as `allow` is narrow: a
  broad `allow` entry defeats every `deny` rule it overlaps with, since
  Claude Code doesn't enforce `deny` against a tool call that `allow`
  already grants. It is not the same thing as the `.claudeignore` file from
  Step 7 below — see that step's notes for why both exist.
- The scoped `Write`/`Edit` entries cover the two things this harness
  actually rewrites in a target repo: `.claude/docs/**` (written by
  `init-harness`, kept current by Gate 6) and `.claude/harness.json` (the
  stack manifest, same). They used to grant `.claude/skills/**` instead —
  a leftover from the original project, where the harness's skills were
  vendored into the repo. In this plugin they live inside the plugin, so a
  target repo has no `.claude/skills/` the harness owns; granting unprompted
  writes there only handed the agent a way to author skill files that steer
  every later session in that repo. Everything else `init-harness` writes
  once (`.claude/settings.json`, `.claudeignore`, `CLAUDE.md`, `.husky/**`)
  is deliberately left to prompt — a one-time scaffolder asking before it
  edits your instruction file is the correct amount of friction.
- `allow` deliberately excludes `Bash(node -e:*)`, `Bash(node -p:*)`,
  `Bash(cat:*)`, `Bash(for *)`, and bare `Write`/`Edit`: each is a generic
  enough primitive to read or overwrite any file in the repo — including
  `.env`, `.git/hooks/*`, and `.claude/settings.json` itself — which routes
  straight around the `deny` list above and the scoped `Write(...)`/
  `Edit(...)` entries. If an agent needs to read a file, it has the `Read`
  tool (subject to `deny`); it doesn't need `cat` or `node -e` as well.
- `Bash(curl:*)` is narrowed to `Bash(curl -s http://localhost:*)` — the only
  legitimate use in this harness is polling the local dev server in `web-qa`.
  An unscoped `curl` is an exfiltration channel to any host.
- `Bash(rm -rf:*)` alone doesn't catch `rm -fr`, `rm -r -f`, `find . -delete`,
  or `git clean`/`git reset --hard` — added as explicit entries. This is
  still prefix matching, not semantic analysis: `Bash` deny rules match the
  start of the command string, so e.g. `find . -type f -delete` (flag before
  `-delete`) or `rm --recursive --force` slip past the literal forms above.
  Treat this whole `Bash` deny list as a speed bump that catches the common
  spellings, not a sandbox that catches every equivalent invocation — a
  determined or careless agent can still construct a destructive command
  these entries don't match.
