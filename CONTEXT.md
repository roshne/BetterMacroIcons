# BetterMacroIcons

**Deps:** LibNAddOn · **SavedVars:** none · **Commands:** `/bmi` (planned) · **UI:** raw WoW API (hooks Blizzard_MacroUI)

Injects a live-search box into `MacroPopupFrame` (the icon picker shown when you click the icon button in the macro editor). Filters the icon grid in real-time as you type, without touching any Blizzard-protected state.

---

## Files

| File | Purpose |
|---|---|
| `icons.lua` | `ns.iconNames` — bundled array of ~32.5k `Interface\Icons\` texture basenames (lowercase), generated from the community wow-listfile. Loaded before `core.lua`. Regenerate when a patch adds icons (see **Regenerating the icon list**). |
| `core.lua` | Namespace init, fileID→name map, search box injection, filter logic. |

---

## Architecture

The addon waits for `ADDON_LOADED` with `addonName == "Blizzard_MacroUI"`, then installs three hooks on `MacroPopupFrame`:

| Hook | When | Action |
|---|---|---|
| `HookScript("OnShow", …)` | Frame shown | Inject search box (once), reset search text, build `fileIDMap`, rebuild `nameIndex`, apply filter |
| `hooksecurefunc(…, "SetIconFilterInternal", …)` | Filter tab changes (Spells/Items/etc.) | Rebuild `nameIndex` from new provider, re-apply text filter |
| `hooksecurefunc(…, "Update", …)` | Blizzard calls `Update()` | Re-apply filter if search is active (prevents Blizzard re-Update from clobbering our provider) |

`HookScript("OnShow")` is used (not `hooksecurefunc(frame, "OnShow")`) because the `<OnShow method="OnShow"/>` XML binding captures the method reference at frame creation time, so the Lua-method hook never fires.

It also wraps `MacroPopupFrame.IconSelector`'s **setup callback** (`SelectorMixin:Get/SetSetupCallback`) once at load: the selector drives every (recycled) grid button through that one callback with `(button, selectionIndex, icon)`, so the wrapper calls Blizzard's original, stashes the current fileID on the button, and attaches an idempotent hover tooltip showing the icon's `Interface\Icons\<name>` path.

---

## Data Structures

```lua
fileIDMap   = {}  -- [fileID int] = lowercase icon name
                  -- built once per session by resolving each ns.iconNames entry via
                  -- GetFileIDFromPath("Interface/Icons/<name>") → fileID
                  -- NOTE: in WoW 12.0 the provider returns integer fileIDs with no name of
                  --       their own, so the bundled list is the searchable name source

nameIndex   = {}  -- [providerIndex] = searchable name string
                  -- rebuilt on every OnShow and SetIconFilterInternal

filteredMap = {}  -- [displayIndex] = providerIndex
                  -- recomputed on every keystroke (and on show/filter change)
                  -- drives SetSelectionsDataProvider

searchText  = ""  -- current lowercased search string; "" means no filter
```

---

## Key Functions

```lua
buildFileIDMap()          -- populate fileIDMap from the bundled ns.iconNames list;
                          -- GetFileIDFromPath("Interface/Icons/<name>") → fileID for each
                          -- no-op if already built (once per session)

iconName(tex)             -- tex: string path or integer fileID → lowercase base name
                          -- strings: strip "INTERFACE\ICONS\" prefix + extension
                          -- integers: look up fileIDMap; returns "" if unknown

rebuildNameIndex(frame)   -- wipe + refill nameIndex from frame.iconDataProvider
                          -- O(numIcons); called on show and filter-type change

applyFilter(frame)        -- wipe + refill filteredMap using nameIndex + searchText
                          -- calls SetSelectionsDataProvider + UpdateSelections to refresh grid

injectSearchBox(frame)    -- one-time injection; grows frame height by SEARCH_H (26px),
                          -- shifts IconSelector down, creates SearchBoxTemplate EditBox
                          -- stored as frame._bmiSearchBox

installTooltips(selector) -- one-time wrap of the IconSelector setup callback; per button
                          -- stores button._bmiIcon (current fileID) and hooks OnEnter/OnLeave
                          -- once (button._bmiHooked). tooltipOnEnter shows iconName(icon) as
                          -- an Interface\Icons path, or "fileID <n>" when unmapped
```

---

## Icon Provider

`MacroPopupFrame.iconDataProvider` is a `C_MacroIconPicker`-style data provider. The relevant surface:

| Method | Returns |
|---|---|
| `GetNumIcons()` | Total count of icons for the current filter |
| `GetIconByIndex(i)` | String path or integer fileID for display index `i` |

`SetSelectionsDataProvider(getterFn, countFn)` + `UpdateSelections()` replaces the grid's content with a custom source — this is the hook point for injecting the filtered view.

---

## Globals Used (luacheck allowlist)

| Global | Source |
|---|---|
| `GetFileIDFromPath` | WoW C function — resolves `"Interface/Icons/<name>"` → integer fileID; used to map each bundled name to the fileID the provider returns |
| `SearchBoxTemplate_OnTextChanged` | Blizzard UI — handles placeholder text behaviour for `SearchBoxTemplate` frames |
| `GameTooltip` | Standard WoW API — the hover tooltip shown on each grid icon |
| `MacroPopupFrame` | Blizzard_MacroUI global — the icon picker frame |
| `CreateFrame`, `hooksecurefunc`, `wipe` | Standard WoW API |

---

## Regenerating the icon list

`icons.lua` is generated from the community **wow-listfile** (`interface/icons/*.blp`), filtered to clean `[a-z0-9_]` basenames, deduped, lowercased. Refresh when a patch adds icons:

```sh
curl -sL https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv \
  | grep -iE '^[0-9]+;interface/icons/[^;]+\.blp$' \
  | sed -E 's#^[0-9]+;interface/icons/##i; s#\.blp$##i' \
  | tr 'A-Z' 'a-z' | grep -E '^[a-z0-9_]+$' | sort -u
```

Wrap each line as `"<name>",` inside `ns.iconNames = { … }`. Names that don't resolve on the live client (`GetFileIDFromPath` returns nil/0) are simply skipped at load, so a slightly stale list is harmless — it just won't name brand-new icons until regenerated.

---

## Gotchas

- **`injected` guard**: `injectSearchBox` is idempotent — the search box is created only once even if `OnShow` fires multiple times (Blizzard can show/hide the frame without reloading).
- **`fileIDMap` is session-stable**: Built once; the icon set doesn't change during a client session. `buildFileIDMap` is a no-op after the first call.
- **Filter ordering**: `nameIndex` must be rebuilt before `applyFilter` is called. `applyFilter` reuses the existing `nameIndex` on every keystroke; `rebuildNameIndex` is only called on provider change.
- **`SetSelectionsDataProvider` replaces Blizzard's source**: After our filter is active, Blizzard's `Update()` call would reset the provider back. The `Update` hook re-applies our filter whenever `searchText != ""` to keep the grid consistent.
- **Frame height delta**: `SEARCH_H = 26` — the frame is grown by this amount on first inject. `IconSelector`'s `TOPLEFT` anchor is shifted down by the same delta.
- **Recycled grid buttons**: the IconSelector pools/reuses buttons as you scroll, so the tooltip `OnEnter` reads `button._bmiIcon` (refreshed every setup-callback run) rather than capturing a fileID at hook time — otherwise a reused button would tooltip a stale icon. The `OnEnter`/`OnLeave` hooks are attached once per button (`button._bmiHooked`), and the setup-callback wrap itself once per selector (`selector._bmiTooltips`).
- **Tooltips are grid-only**: the "Currently Selected" preview button (`SelectedIconButton`) is intentionally not covered — only the scrollable icon grid gets tooltips.
