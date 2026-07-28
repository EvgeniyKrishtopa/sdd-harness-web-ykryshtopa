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
      "Bash(curl:*)",
      "Bash(node -p:*)",
      "Bash(node -e:*)",
      "Bash(which:*)",
      "Bash(cat:*)",
      "Bash(mkdir:*)",
      "Bash(echo:*)",
      "Bash(sleep:*)",
      "Bash(kill:*)",
      "Bash(for *)",
      "Bash(git commit -m *)",
      "Bash(git checkout *)",
      "Bash(git status:*)",
      "Bash(git diff:*)",
      "Bash(git fetch:*)",
      "Bash(git pull --ff-only:*)",
      "Bash(git ls-remote:*)",
      "Bash(gh pr create:*)",
      "Write",
      "Edit",
      "Write(./.claude/docs/**)",
      "Edit(./.claude/docs/**)",
      "Write(./.claude/skills/**)",
      "Edit(./.claude/skills/**)"
    ],
    "deny": [
      "Read(**/.env)",
      "Read(**/.env.*)",
      "Bash(cat .env:*)",
      "Bash(rm -rf:*)",
      "Bash(npm install:*)",
      "Bash(npm i:*)",
      "Bash(pnpm add:*)",
      "Bash(yarn add:*)",
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
- The three other package managers' `add`/`install` commands stay in `deny`
  **regardless of which one this project actually uses** (defense in depth —
  an agent can't route around the install-command block by invoking a
  different package manager than the one detected).
- `Bash(npx openspec:*)` / `Bash(openspec:*)` match the CLI **binary** name,
  which is `openspec` regardless of package name. The npm package installed
  in Step 2 is `@fission-ai/openspec` (the bare `openspec` package is an
  unrelated empty squatter) — that only affects the install command, not
  these permission entries.
- `{{BUILD_DIR}}` is `dist` for Vite, `.next` for Next.js — read the detected
  framework from Step 1, don't hardcode one.
- This `permissions.deny` list is the actually-enforced, un-bypassable
  mechanism for hard blocks (secrets, destructive commands). It is not the
  same thing as the `.claudeignore` file from Step 8 below — see that step's
  notes for why both exist.
