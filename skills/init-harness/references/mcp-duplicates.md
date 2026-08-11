# Telling the user they already run their own copy of these MCP servers

Read this from Step 10, as part of the report. It changes nothing and
installs nothing — it names a condition the user cannot see from inside a
session, and lets them decide.

## The condition

This plugin ships two MCP servers in its own `.mcp.json`, at pinned
versions: `@playwright/mcp` for Gate 3 and `@upstash/context7-mcp` for
library docs. A user may independently have a server for either one in their
own configuration — commonly at `@latest`, and commonly under the plain name
`playwright` or `context7`.

Nothing breaks when that happens. The two are separate servers with
separately namespaced tools (`mcp__plugin_<plugin>_<server>__<tool>` for
this plugin's, `mcp__<server>__<tool>` for theirs), so neither shadows the
other and neither changes the other's version. What the user gets is a
second process they may not have meant to run, started and kept resident for
the whole session.

Gate 3 in particular no longer touches theirs at all:
`agents/web-qa-manual-tester.md` lists only the plugin-namespaced tools,
precisely so a browser pass can't silently run on an unpinned version. So a
duplicate Playwright MCP is pure cost — no benefit, no harm beyond the
process.

## Detecting it

```bash
claude mcp list 2>/dev/null
```

Each line is `<name>: <command-or-url> - <status>`. Look for a line whose
name is exactly `playwright` or `context7` — no `plugin:` prefix. Those are
the user's own. Lines that do carry a `plugin:` prefix are plugins' servers,
this one's included, and are not duplicates of anything.

The command being unavailable, slow, or printing something unparseable is
not a failure worth reporting: skip the check silently in that case. It is
an optional nicety, not one of the things setup proves.

## What to say

Only when a duplicate was actually found, one short paragraph in Step 10's
report, naming which one(s): the user runs their own `<name>` MCP server as
well as the plugin's pinned copy; the harness always uses its own, so the
versions can't collide; the only cost is an extra process, and `/mcp`
disables either side if they'd rather run one.

Two things not to say, because both are wrong: that they must remove theirs
(they mustn't — their own server may serve other work in the same session),
and that disabling the *plugin's* copy is equivalent (it isn't — Gate 3
would then have no tools that resolve, and its agent refuses to launch).

Found nothing → say nothing. This is the one report line whose absence
carries no information worth a sentence.
