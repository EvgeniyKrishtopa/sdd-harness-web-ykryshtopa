# Step 2c — upgrading the OpenSpec workflow profile

Read this only when Step 2c's check found one of `new`, `continue`, `verify`
missing from the workflow list. When all three are present there is nothing
here to do, whatever `profile` says.

## Why this harness needs more than the Core profile

`openspec init` sets up the **Core** profile (`propose`, `explore`, `apply`,
`update`, `sync`, `archive`). This harness's gates need the **Expanded**
workflow set (adds `new`, `continue`, `ff`, `bulk-archive`, `verify`,
`onboard`) — Gate 1 (`architecture-review`) is designed to fire once
`design.md` is done but before specs/tasks are drafted, and Gate 2
(`spec-review`) waits for every artifact's step-by-step completion. Neither
point of insertion exists in Core's single-shot `propose` flow.

There is no literal `"expanded"` profile value — in OpenSpec's config schema
`profile` is the enum `core | custom`. Expanded is expressed as
`profile: "custom"` plus the full `workflows` list. The CLI derives
`profile` automatically from which workflows are selected.

## Why the check is on the workflow list, not the profile string

`profile: custom` only means the user picked their own selection — it says
nothing about *which* workflows are in it. A machine can sit at
`profile: custom` with, say, `propose, explore, continue, apply, update,
sync, archive` — a perfectly valid custom profile that is still missing
`new` and `verify`, and so still can't run Gates 1-2 at their designed
insertion points. That state is common (it's what a partial pass through the
interactive picker leaves behind) and it must be treated exactly like `core`.

The workflows this harness requires are **`new`, `continue`, `verify`**.
The rest of the Expanded set (`ff`, `bulk-archive`, `onboard`) is nice to
have and not worth blocking on.

## This setting is global — never change it silently

It lives in `~/.config/openspec/config.json` (or
`$XDG_CONFIG_HOME/openspec/config.json`), not anywhere inside this repo.
That means: it isn't committed, a teammate cloning this repo won't have it
just because the repo does, CI never has it unless configured separately,
and changing it on this machine affects **every other OpenSpec project** the
user has, not just this one. Because of that blast radius, never change it
silently.

## The procedure

Explain to the user, plainly, before doing anything — naming which of the
three are missing:

- this harness requires the Expanded workflow set to work as designed;
- the setting is global to their machine, not scoped to this repo;
- it will change OpenSpec's behavior in their other OpenSpec projects too.

Then offer two ways to proceed, and let the user pick. There is no third
way: `openspec config profile` accepts exactly one preset shortcut, `core`
(verified against @fission-ai/openspec 1.7.0 — any other preset name exits
with "Unknown profile preset"), and outside a TTY it refuses to run at all
with "Interactive mode required". So the Expanded set can only be reached by
a human at a prompt, or by writing the file.

- **Default**: ask the user to run `npx openspec config profile` themselves
  in their own terminal (it's an interactive multi-select — not something to
  drive non-interactively through the agent's Bash tool) and select the full
  workflow set, then confirm back when done.
- **Direct write**: only with the user's explicit go-ahead, write
  `~/.config/openspec/config.json` directly with:
  ```json
  {
    "profile": "custom",
    "delivery": "both",
    "workflows": ["propose", "explore", "new", "continue", "apply",
                  "update", "ff", "sync", "archive", "bulk-archive",
                  "verify", "onboard"],
    "featureFlags": {}
  }
  ```

Do not pick a path or write this file without the user's explicit
confirmation — this is someone's global environment, not project state.

Once the profile is set, run `npx openspec update` in the repo root to apply
the new workflow selection to this project's `openspec/` instructions, then
return to Step 2d, which re-checks and stops the run if it still didn't take.
