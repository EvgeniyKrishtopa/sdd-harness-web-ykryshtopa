# The Claude Code version floor, and the two places it is checked

Read this at the very start of `init-harness`, before Step 0 decides
first-time-install vs upgrade. The floor used to live only in the README,
where nothing enforced it: a repo set up on an older Claude Code was recorded
as fully configured, and the breakage surfaced later as a check finding
nothing rather than as an error anyone could trace back to its cause.

## The floor

**Claude Code >= 2.1.220.** One number covering four behaviours this harness
depends on, each of which fails *silently* rather than loudly when absent:

- plugin-bundled MCP tool names (`mcp__plugin_<plugin>_<server>__<tool>`) —
  without them Gate 3's agent resolves no browser tools at all;
- `Edit(path)`/`Read(path)` permission rules being honoured (2.1.210+) —
  what the generated `permissions` block is written against;
- a subagent with an unresolvable `tools:` list refusing to launch rather
  than running toolless (2.1.208+);
- `stop_hook_active` in the `Stop` hook, without which the typecheck guard
  has no loop guard.

Raising this number is a release decision, not a detail: it goes up only when
the plugin actually starts depending on newer behaviour. The same literal
appears in three files — this one, `hooks/hooks.json`'s `SessionStart`
command, and the README's Requirements section — and
`tests/smoke-json-schema.sh` compares all three, so they cannot drift apart.

## Reading the running version

```bash
cc_version="$("${CLAUDE_CODE_EXECPATH:-claude}" --version 2>/dev/null | grep -oE '[0-9]+\.[0-9]+\.[0-9]+' | head -1)"
```

`CLAUDE_CODE_EXECPATH` is the binary this session is actually running, which
is the version that matters — a `claude` on `PATH` can be a different,
newer install than the one hosting the session. Fall back to `PATH` only
when that variable is unset.

Compare as versions, never as strings (`2.1.9` sorts above `2.1.220`
lexically), the same way Step 0 compares plugin versions:

```bash
older="$(printf '%s\n%s\n' "$cc_version" "2.1.220" | sort -V | head -1)"
```

`$cc_version` is below the floor when it isn't equal to `2.1.220` and is the
`$older` of the two.

## The three outcomes

1. **At or above the floor** → say so in one line, naming the version, and
   continue with Step 0.
2. **Below the floor** → **stop**, exactly as Step 2a stops on an old Node.
   Name both numbers, say that what this prevents are silent failures (a
   browser gate that finds no tools, permission rules that don't apply, a
   subagent that runs without the tools it declares), and tell the user to
   upgrade Claude Code and re-run this skill. Write nothing: no manifest, no
   `harnessVersion`, no docs. A repo half-configured against an unsupported
   runtime is worse than one not configured at all.
3. **Unreadable** — no `claude` on `PATH` and no `CLAUDE_CODE_EXECPATH`, or
   nothing a version could be parsed out of → **do not stop.** Print one
   explicit line saying the check was skipped and why, name the floor so the
   user can check by hand, and continue. The floor is still a requirement;
   what's missing is only this skill's ability to confirm it, and blocking
   setup on a `PATH` quirk would cost more than it protects.

Outcome 3 is never silent here. A skipped check that says nothing reads, to
a later run and to the user, exactly like a check that passed.

## Why the session banner checks it too

`init-harness` runs once per repository; the version can change under it any
day after that, and a repo configured months ago never re-checks. So
`hooks/hooks.json`'s `SessionStart` command runs the same comparison at every
session start and prints a two-line warning above the git banner when the
running version is below the floor.

That hook is deliberately **quieter** than outcome 3 above: when the version
can't be read it prints nothing at all. A warning a user sees every single
session, in every repository, for a condition that is usually just a `PATH`
quirk, is noise that trains people to ignore the banner — and the one place
that must not be silent about it, setup, already isn't.
