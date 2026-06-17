# Better Macro Icons

Adds a **live search box** and **filename tooltips** to the macro icon picker — the icon grid shown when you click the icon button while creating or editing a macro.

WoW 12.0 stopped exposing icon names through the macro API (the picker now serves bare texture IDs), so the built-in picker has no way to search. Better Macro Icons bundles the full `Interface\Icons` name list and resolves it back to those IDs, making every icon findable by name again.

## Features

- **Search box** at the top of the icon picker — type any part of an icon's file name (e.g. `frostbolt`, `inv_sword`, `spell_fire`) to filter the grid live as you type.
- **Filename tooltips** — hover any icon in the grid to see its texture name.
- Works across the picker's filter tabs (All Icons / Spell / Item) and while scrolling.

## Usage

Open the macro UI (`/macro`), create or edit a macro, and click its icon button. The search box appears above the icon grid; start typing to filter, and hover an icon to see its name.

## Commands

| Command | Description |
|---|---|
| `/bmi debug` | Print search diagnostics (open the icon picker first) |

## Dependencies

- **LibNAddOn** — must be installed and enabled.

## Saved data

None. Better Macro Icons stores no saved variables.
