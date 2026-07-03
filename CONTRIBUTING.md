# Contributing

This repo is a single standalone WoW addon, checked out (or symlinked) directly into a
WoW installation's `Interface/AddOns/` directory. There is no build step and no package
manager — edits are live on the next `/reload`.

For a code-level map of the addon, start at [CONTEXT.md](CONTEXT.md). Coding conventions
are specified in [CLAUDE.md](CLAUDE.md) — the highlights are below.

## Code style

- 2-space indent.
- Everything belongs on the addon namespace or a file-local — no standalone globals.
- LuaLS annotations (`---@class`, `---@field`, `---@param`, `---@return`) on public surface.
- WoW runs **Lua 5.1** — no `goto`, no `//`, no bitwise operators, no `table.unpack`.
- Files stay within ~200–300 lines; split by responsibility beyond that. The bundled
  `icons.lua` data table is the deliberate exception.

## Namespace imports

Every file declares the addon namespace with a typed import so the Lua language server
can link fields across files.

The setup file (the one that calls `LibNAddOn`):

```lua
---@class BetterMacroIcons: AddOn
local ns = LibNAddOn(...)
```

Every other file:

```lua
---@class BetterMacroIcons
local ns = select(2, ...)
```

## Testing

- **In-game**: `/reload` after changes; open a macro's icon picker to exercise search and
  tooltips. `/bmi debug` prints diagnostics; `/dump <expr>` and `/run <lua>` inspect live
  data.
- **Lint**: `luacheck` (config in `.luacheckrc`). CI is **strict** — any warning fails the
  build, and the repo lints clean. Keep it that way. When you add a WoW global, add it to
  `read_globals`.
- CI runs luacheck (and busted, if specs are ever added) on every PR and push to `main`
  (`.github/workflows/ci.yml`).

## Regenerating the icon list

`icons.lua` is generated from the community wow-listfile. See **Regenerating the icon
list** in [CONTEXT.md](CONTEXT.md) for the exact command — refresh it when a patch adds
icons.

## Versioning

`## Version:` in the `.toc` is `MAJOR.MINOR.PATCH-rREVISION`, where `MAJOR.MINOR.PATCH`
mirrors the WoW client version (e.g. `12.0.7-r0`). Bump `MAJOR.MINOR.PATCH` when adding
support for a new client version (alongside the `## Interface:` field); increment
`-rREVISION` for subsequent releases within the same client version. Doc-only (`.md`)
changes don't warrant a revision bump.
