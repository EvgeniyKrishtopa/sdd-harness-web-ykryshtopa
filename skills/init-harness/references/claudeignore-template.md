# `.claudeignore` — what it is and isn't

**`.claudeignore` is not an official Claude Code mechanism.** There is no
built-in file of this name that Claude Code reads on its own — this has been
a long-requested feature, and Anthropic's stated position is to use
`permissions.deny` (see `permissions-template.md`) or a `PreToolUse` hook
instead. Shipping a `.claudeignore` file with no enforcement behind it would
just be a file nobody reads.

This plugin makes the file real by pairing it with the `claudeignore-guard`
`PreToolUse` hook in `hooks/hooks.json`, which reads `.claudeignore` (simple
glob patterns, one per line, `#` comments) and denies `Read`/`Grep` calls
whose target path matches a pattern.

## Division of responsibility with `permissions.deny`

- **`permissions.deny`** — the actually-enforced, can't-be-routed-around
  block for anything sensitive: secrets, `.env` files, destructive commands.
  Enforced by Claude Code itself, not by this plugin's own hook logic.
- **`.claudeignore` + the guard hook** — a lower-stakes, gitignore-style
  convenience layer for keeping build output, caches, and coverage reports
  out of context (noise reduction, not security). It uses simple glob
  matching (directory/segment/suffix), not full gitignore semantics — no
  negation (`!pattern`), no `**` recursive-wildcard nuance.

Don't rely on `.claudeignore` alone for anything that must never be read —
put that in `permissions.deny` instead, where init-harness already writes it.

## Template written to the target repo's `.claudeignore`

```
# Read/context noise reduction — NOT a security boundary.
# Secrets and destructive commands are blocked via permissions.deny in
# .claude/settings.json (see .claude/docs/review-gates.md), not here.
node_modules
{{BUILD_DIR}}
coverage
.git
*.log
{{LOCKFILE}}
```

Substitute `{{BUILD_DIR}}` (`dist` or `.next`) and `{{LOCKFILE}}` the same way
as `permissions-template.md`. Do not overwrite an existing `.claudeignore`
that already has content — append missing lines instead.
