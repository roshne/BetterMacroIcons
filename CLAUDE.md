# Better Macro Icons — Claude Instructions

## First Step: Read CONTEXT.md

**At the start of every session, read `CONTEXT.md` in this directory.** It contains the file map, architecture, data structures, key functions, the icon-list regeneration command, and the gotchas for this addon.

## Project Overview

Standalone WoW Retail addon by Roshne (Interface 120000+). Injects a live-search box and filename tooltips into the macro icon picker (`MacroPopupFrame`). Depends on **LibNAddOn**. No build step, no package manager, no saved variables. All in-game testing is done via `/reload`.

## Coding Conventions

| Convention | Detail |
|---|---|
| Namespace | Typed import in every file — see **Namespace Imports & Typing** below |
| Addon init | `local ns = LibNAddOn(...)` (assignment form) in the setup file |
| Event handling | `ns:registerEvent("EVENT", handler)` |
| Slash commands | `ns:registerCommand("name", "subcommand", handler, "description")` |
| Hooking Blizzard frames | Never access protected/secure state; the icon picker is unprotected, so hooks here are taint-free |
| LuaLS annotations | `---@class`, `---@field`, `---@param`, `---@return` |
| No error handling | WoW API errors surface in-game; no defensive nil-checks on internal invariants |
| No standalone utilities | Everything belongs on the addon namespace or a local within the file |
| Testing | In-game via `/reload`; `luacheck` for static analysis |

## Namespace Imports & Typing

The setup file (the one that calls `LibNAddOn`):

```lua
---@class BetterMacroIcons: AddOn
local ns = LibNAddOn(...)
```

All other files import the namespace and re-open the class to add fields:

```lua
---@class BetterMacroIcons
local ns = select(2, ...)
```

`icons.lua` adds the `ns.iconNames` data table this way; `core.lua` is the setup file.

## Lua 5.1

WoW runs **Lua 5.1**. No `goto`/`::label::`, no `//` integer division, no bitwise operators (use the `bit` library), no `table.unpack`/`table.move` (use `unpack()`).

## Versioning

The `## Version:` field in the `.toc` uses the format **`MAJOR.MINOR.PATCH-rREVISION`**, where `MAJOR.MINOR.PATCH` mirrors the WoW client version (e.g. `12.0.7-r0`) and `REVISION` is a zero-based counter that resets each patch cycle. `r0` is the initial release adding support for that client version (at minimum a client-version bump in the `.toc`).

## File Size

Keep individual files to **200–300 lines maximum** (the bundled `icons.lua` data table is the deliberate exception). Split logic by responsibility beyond that.

## Lint

`luacheck` is **strict** — any warning fails CI (`.github/workflows/test.yml`) and the repo lints clean; keep it that way. When you use a new WoW global, add it to `.luacheckrc`'s `read_globals`. Config lives in `.luacheckrc`.

## In-Game Debugging

Use `/dump <expr>` or `/run <lua>` to inspect live data (output appears in chat, can't be copied, truncates if long). `/bmi debug` prints search diagnostics (open the icon picker first).

## Key Gotchas

See `CONTEXT.md` for the full list. The load-bearing ones:

- **`HookScript("OnShow")`, not `hooksecurefunc`** — `MacroPopupFrame`'s `<OnShow method="OnShow"/>` XML binding captures the method reference at creation, so a Lua-method hook never fires.
- **Recycled grid buttons** — the icon grid pools buttons while scrolling; read the current fileID off the button at hover time, never capture one at hook time.
- **Bundled name list** — the picker serves integer fileIDs with no names in 12.0; `ns.iconNames` (resolved via `GetFileIDFromPath`) is the only name source. Regenerate it on patch per `CONTEXT.md`.
