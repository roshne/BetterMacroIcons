# BetterMacroIcons

**Deps:** LibNAddOn (+ optional LibNUI) · **SavedVars:** `BetterMacroIconsDB` (account-wide, `X-NUI-DB`, DB v1) · **Commands:** `/bmi open`, `/bmi scan`, `/bmi coverage`, `/bmi debug`, `/bmi cleanup [preview]` · **UI:** raw WoW API (hooks Blizzard_MacroUI)

Injects a live-search box into `MacroPopupFrame` (the icon picker shown when you click the icon button in the macro editor). Filters the icon grid in real-time as you type, without touching any Blizzard-protected state. Icons are searchable by their bundled file name **plus** two optional term sources: spell names read from the spellbook (`scan.lua`) and user-curated aliases (`aliases.lua`).

---

## Files

| File | Purpose |
|---|---|
| `icons.lua` | `ns.iconNames` — bundled array of ~32.5k `Interface\Icons\` texture basenames (lowercase), generated from the community wow-listfile. Loaded before `core.lua`. Regenerate when a patch adds icons (see **Regenerating the icon list**). |
| `core.lua` | **Setup file** (calls `LibNAddOn`, so it loads first). fileID→name map, search box injection, filter logic, multi-token matching, tooltips + right-click wiring. Exposes `ns.IconName` and `ns.refreshSearch`; reads the two optional term seams defensively. |
| `scan.lua` | **Removable module.** Spellbook scan → `ns.SpellTermsFor(fileID)`. Spec/race-keyed pooled store, plus `/bmi coverage` (which class/specs & races are captured/missing). Delete this file + its `.toc` line and the addon still works (name search + aliases) without spell terms. |
| `aliases.lua` | Curated user aliases: `MigrateDB`, `ns.AliasTermsFor(fileID, name)`, and the right-click context menu + add-term popup (`ns.onIconRightClick`). |
| `cleanup.lua` | **Removable module.** Registers `/bmi cleanup [preview]` — deletes duplicate macros leaked by VuhDo (`VuhDoDCShieldData`/`Names`) and Plumber (`Plumber Housing Macro`). `LEAK_MACROS` name list + count/delete over both macro blocks (account + character, base from `Constants.MacroConsts.MAX_ACCOUNT_MACROS`). No DB, no seams — delete the file + its `.toc` line to remove. |

**TOC load order:** `icons.lua`, `core.lua`, `scan.lua`, `aliases.lua`, `cleanup.lua`. `core.lua` is first because it calls `LibNAddOn(...)`; `scan.lua`/`aliases.lua`/`cleanup.lua` make load-time `ns:registerEvent`/`ns:registerCommand` calls that need the wired namespace. All cross-module reads happen at runtime via `ns`, so beyond "setup first" the order is not otherwise significant.

---

## Architecture

The addon waits for `ADDON_LOADED` with `addonName == "Blizzard_MacroUI"`, then installs three hooks on `MacroPopupFrame`:

| Hook | When | Action |
|---|---|---|
| `HookScript("OnShow", …)` | Frame shown | Inject search box (once), reset search text, build `fileIDMap`, rebuild `nameIndex`, apply filter |
| `hooksecurefunc(…, "SetIconFilterInternal", …)` | Filter tab changes (Spells/Items/etc.) | Rebuild `nameIndex` from new provider, re-apply text filter |
| `hooksecurefunc(…, "Update", …)` | Blizzard calls `Update()` | Re-apply filter if search is active (prevents Blizzard re-Update from clobbering our provider) |

`HookScript("OnShow")` is used (not `hooksecurefunc(frame, "OnShow")`) because the `<OnShow method="OnShow"/>` XML binding captures the method reference at frame creation time, so the Lua-method hook never fires.

It also wraps `MacroPopupFrame.IconSelector`'s **setup callback** (`SelectorMixin:Get/SetSetupCallback`) once at load: the selector drives every (recycled) grid button through that one callback with `(button, selectionIndex, icon)`, so the wrapper calls Blizzard's original, stashes the current fileID on the button, and attaches an idempotent hover tooltip **and** a right-click handler.

### Module seams

`core.lua` owns the picker/search; the two term modules contribute searchable text through single-symbol seams, all read defensively (`(ns.Fn and ns.Fn(...)) or ""`) so either module can be removed:

| Seam | Provider | Consumer |
|---|---|---|
| `ns.IconName(tex)` | `core.lua` | `scan`/`aliases` — key aliases, resolve display names |
| `ns.refreshSearch()` | `core.lua` | `scan`/`aliases` — re-index + re-filter the live picker after term data changes |
| `ns.SpellTermsFor(fileID)` | `scan.lua` | `core.lua` — spell names folded into `nameIndex` + tooltip |
| `ns.AliasTermsFor(fileID, name)` | `aliases.lua` | `core.lua` — aliases folded into `nameIndex` + tooltip |
| `ns.onIconRightClick(owner, fileID)` | `aliases.lua` | `core.lua` — right-click on a grid button |

---

## Data Structures

```lua
-- core.lua
fileIDMap   = {}  -- [fileID int] = lowercase icon name; built once/session from ns.iconNames
nameIndex   = {}  -- [providerIndex] = "<name> <spellTerms> <aliasTerms>" searchable blob
filteredMap = {}  -- [displayIndex] = providerIndex; recomputed each keystroke
searchText  = ""  -- current lowercased query; "" = no filter
searchTokens= {}  -- whitespace tokens of searchText (scratch, rebuilt per filter pass)

-- scan.lua (persisted in ns.db, lazy-seeded here)
db.spellTermsBySpec = { [specID] = { [fileID] = " name1 name2 " } }  -- class/spec spells
db.spellTermsByRace = { [raceID] = { [fileID] = " name1 name2 " } }  -- racials + general line
                                                                    -- raceID canonicalised (canonRace)
mergedSpellTerms    = { [fileID] = " name1 name2 " }  -- in-memory union of all sections

-- scan.lua coverage data (mirrored from Warbandeer_Collected/data/models.lua — hand-verified)
PLAYABLE_RACES = { 1,2,3,…,84,86 }               -- 26 canonical playable race IDs (86 = Haranir)
RACE_ALIAS     = { [24]=25,[26]=25,[70]=52,[85]=84 }  -- faction/neutral variants → canonical

-- aliases.lua (persisted in ns.db, seeded by MigrateDB)
db.aliases  = { [nameKey] = { "term1", "term2" } }  -- nameKey = IconName(fileID) or "fileid:N"
db.version  = 1
```

Terms are stored space-delimited with a leading + trailing space so a single `:find(" name ")` both substring-matches and dedupes. Search is plain substring over the `nameIndex` blob; multi-word queries require **every** whitespace token to be present (`matchesAll`, order-independent).

**Store keying rationale:** spell terms are keyed by **fileID** (the scan already has each spell's `iconID`, so no name-map build is needed — `SPELLS_CHANGED` upkeep stays cheap; the store is a frequently-regenerated cache, so rare cross-patch fileID drift self-heals). Aliases are keyed by **name** (write-once, so patch-stability matters; right-click always has the map built). Spell data is keyed by spec/race (static game data) so each is captured once and pooled account-wide; aliases are account-wide vocabulary.

---

## Key Functions

```lua
-- core.lua
buildFileIDMap()          -- populate fileIDMap from ns.iconNames (once/session)
iconName(tex) / ns.IconName(tex)  -- tex path|fileID → lowercase base name ("" if unknown)
rebuildNameIndex(frame)   -- refill nameIndex = name + SpellTermsFor + AliasTermsFor (guarded)
tokenize(str) / matchesAll(name, tokens)  -- multi-token AND matcher
applyFilter(frame)        -- refill filteredMap (empty / incremental-narrow / full-scan branches)
injectSearchBox(frame)    -- one-time; grows frame by SEARCH_H (26px), adds SearchBoxTemplate box
installButtonHandlers(sel)-- one-time wrap of the setup callback; per-button tooltip + OnMouseUp
tooltipOnEnter(button)    -- name line + "Spells:"/"Aliases:" lines (via the seams)
ns.refreshSearch()        -- rebuildNameIndex + applyFilter if the picker is shown

-- scan.lua
scanSpells(force)         -- scan Player bank into bySpec[specID]/byRace[canonRace(raceID)]; force
                          -- wipes this char's sections first, else additive merge; rebuilds; returns count
rebuildMerged()           -- union all spec+race sections into mergedSpellTerms (deduped)
ns.SpellTermsFor(fileID)  -- pooled spell names for an icon (or "")
ns.SpellTermsCount()      -- diagnostic: total icons carrying pooled spell terms (tab-independent)
queueScan()               -- SPELLS_CHANGED debounce via ns:after(300) (not ns:delay)
canonRace(raceID)         -- faction/neutral variant → canonical race id (RACE_ALIAS)
/bmi coverage             -- specs via API, races vs PLAYABLE_RACES; missing + untracked, shown in the
                          -- LibNUI copy window (ShowCopyWindow) when present, else chat

-- aliases.lua
ns:MigrateDB()            -- seed db.version=1, db.aliases={} (non-destructive)
ns.AliasTermsFor(fileID, name)  -- curated terms for an icon, space-joined (or "")
addTerm(key, text) / removeTerm(key, text)  -- mutate db.aliases[key], then refreshSearch
ns.AliasCount()           -- diagnostic: total icons with curated aliases
ns.onIconRightClick(owner, fileID)  -- MenuUtil context menu: add term / remove-term submenu
```

---

## Icon Provider

`MacroPopupFrame.iconDataProvider` is a `C_MacroIconPicker`-style data provider:

| Method | Returns |
|---|---|
| `GetNumIcons()` | Total count of icons for the current filter |
| `GetIconByIndex(i)` | String path or integer fileID for display index `i` (integer fileID in 12.0) |

`SetSelectionsDataProvider(getterFn, countFn)` + `UpdateSelections()` replaces the grid's content with our filtered view.

## Spellbook API (scan.lua)

`C_SpellBook.GetNumSpellBookSkillLines()` → `GetSpellBookSkillLineInfo(i)` (`specID` nil for the General/racial line, `itemIndexOffset`, `numSpellBookItems`) → `GetSpellBookItemInfo(slot, Enum.SpellBookSpellBank.Player)` → `.iconID` (fileID) + `.name`. Lines with a `specID` go to the spec bucket; the rest (racials + class-base) go to the race bucket keyed by `select(3, UnitRace("player"))`.

---

## Globals Used (luacheck allowlist)

| Global | Source / use |
|---|---|
| `GetFileIDFromPath` | Resolve `"Interface/Icons/<name>"` → fileID for the name map |
| `SearchBoxTemplate_OnTextChanged` | Blizzard placeholder-text handling for the search box |
| `GameTooltip` | Hover tooltip on each grid icon |
| `MacroPopupFrame` | Blizzard_MacroUI icon picker frame |
| `CreateFrame`, `hooksecurefunc`, `wipe`, `table` | Standard WoW/Lua API |
| `MacroFrame`, `IconSelectorPopupFrameModes`, `InCombatLockdown`, `C_AddOns`, `ShowUIPanel` | `core.lua` — `/bmi open`: load + show the macro UI and the picker on demand (`MacroPopupFrame` is a *written* global here — `.mode` is set) |
| `C_SpellBook`, `Enum`, `UnitRace` | `scan.lua` — spellbook scan + spec/race keys |
| `GetNumClasses`, `GetClassInfo`, `C_SpecializationInfo`, `GetSpecializationInfoForClassID`, `C_CreatureInfo` | `scan.lua` — `/bmi coverage`: enumerate class/specs + resolve race names |
| `LibNUI` | `scan.lua` — optional; `/bmi coverage` uses `LibNUI.ShowCopyWindow` (the `/wdebug` widget) when present, else chat. `## OptionalDeps: LibNUI` in the toc orders the load |
| `MenuUtil`, `StaticPopup_Show`, `StaticPopupDialogs`, `ACCEPT`, `CANCEL` | `aliases.lua` — right-click menu + add-term popup (`StaticPopupDialogs` is a **writable** global) |
| `InCombatLockdown`, `GetNumMacros`, `GetMacroInfo`, `GetMacroIndexByName`, `DeleteMacro`, `Constants`, `MAX_ACCOUNT_MACROS` | `cleanup.lua` — `/bmi cleanup`: enumerate + delete leaked macros (`Constants.MacroConsts.MAX_ACCOUNT_MACROS` with `MAX_ACCOUNT_MACROS`/`120` fallback for the character-block base) |

Keep `.luacheckrc` and `.luarc.json` in sync when adding a global (CI only lints the former; the latter feeds the editor).

---

## Regenerating the icon list

`icons.lua` is generated from the community **wow-listfile** (`interface/icons/*.blp`), filtered to clean `[a-z0-9_]` basenames, deduped, lowercased. Refresh when a patch adds icons:

```sh
curl -sL https://github.com/wowdev/wow-listfile/releases/latest/download/community-listfile.csv \
  | grep -iE '^[0-9]+;interface/icons/[^;]+\.blp$' \
  | sed -E 's#^[0-9]+;interface/icons/##i; s#\.blp$##i' \
  | tr 'A-Z' 'a-z' | grep -E '^[a-z0-9_]+$' | sort -u
```

Wrap each line as `"<name>",` inside `ns.iconNames = { … }`. Names that don't resolve on the live client (`GetFileIDFromPath` returns nil/0) are simply skipped at load, so a slightly stale list is harmless.

---

## Gotchas

- **`scan.lua` is removable.** Everything about spell terms lives there behind `ns.SpellTermsFor`; `core.lua` reads it guarded. Its DB sub-tables (`spellTermsBySpec`/`spellTermsByRace`) are lazy-seeded inside `scan.lua` and untouched by `MigrateDB`, so deleting the file leaves no dangling reference — the orphaned data just lingers in SavedVariables.
- **Setup file loads first.** `core.lua` calls `LibNAddOn`; `scan.lua`/`aliases.lua` `ns:register*` at load time and would nil-error if loaded before it.
- **`nameIndex` entries are never empty** now — each is `name .. " " .. spellTerms .. " " .. aliasTerms` — so search substring-matches across all three sources in one pass.
- **Incremental-narrow stays valid for multi-token.** A string-prefix-extended query only tightens each token, so matches remain a subset of the current `filteredMap`; `applyFilter` narrows in place rather than rescanning.
- **Right-click via `OnMouseUp`, not `RegisterForClicks`** — registering clicks on the selector button would disturb Blizzard's left-click selection. The handler reads `button._bmiIcon` (refreshed each setup-callback run) so recycled buttons stay correct.
- **`SPELLS_CHANGED` upkeep uses `ns:after` (not `ns:delay`)** — `ns:delay` keeps a single timer that core already uses for the keystroke debounce; sharing it would drop one or the other. `ns:after` allows an independent debounced scan.
- **Additive merge = no redundant rescans.** Default (non-forced) scans only add names not already recorded, so a fully-captured spec/race and any alt of it do no meaningful work. `/bmi scan` forces a wipe + refill of the current character's spec/race sections.
- **Coverage race data is a mirror.** `PLAYABLE_RACES` / `RACE_ALIAS` in `scan.lua` are copied from the hand-verified `Warbandeer_Collected/data/models.lua` (BMI can't read that addon's namespace at runtime). Race keys are canonicalised at store time; `/bmi coverage` resolves names via `GetRaceInfo` and skips ids the client doesn't recognise, so a stale list degrades gracefully and any captured race not in the list is reported as **untracked** (the cue to update the mirror). Specs need no bundled list — they enumerate from the API.
- **`fileIDMap` / spell scan are session/spec-stable** — `buildFileIDMap` is a no-op after first call; spec/race sections are captured once and pooled.
- **Tooltips are grid-only** — the "Currently Selected" preview button (`SelectedIconButton`) is intentionally not covered.
