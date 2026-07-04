# Better Macro Icons

Adds a **live search box**, **spell-name & custom search terms**, and **informative tooltips** to the macro icon picker — the icon grid shown when you click the icon button while creating or editing a macro.

WoW 12.0 stopped exposing icon names through the macro API (the picker now serves bare texture IDs), so the built-in picker has no way to search. Better Macro Icons bundles the full `Interface\Icons` name list and resolves it back to those IDs, making every icon findable by name again — and lets you find icons by the **spell** that uses them or by your **own** words.

## Features

- **Search box** at the top of the icon picker — type any part of an icon's file name (e.g. `frostbolt`, `inv_sword`, `spell_fire`) to filter the grid live as you type.
- **Multi-word search** — type several words separated by spaces (e.g. `fire bolt`) to match icons whose text contains **all** of them, in any order.
- **Search by spell name** — the addon reads your spellbook and maps each spell's icon to the spell's name, so typing `fireball` or `arcane torrent` jumps to the icon that spell uses. This is captured once per class/spec and per race and **pooled across your whole account**, so every character benefits. It stays current automatically as you learn spells; `/bmi scan` forces a refresh.
- **Custom search terms** — right-click any icon in the grid to tag it with a word or phrase, then find it later by that term. Terms are account-wide and persist.
- **Informative tooltips** — hover any icon to see its texture name, plus the spell name(s) and custom terms that make it findable.
- Works across the picker's filter tabs (All Icons / Spell / Item) and while scrolling.

## Usage

Open the macro UI (`/macro`), create or edit a macro, and click its icon button. The search box appears above the icon grid; start typing to filter. Hover an icon to see its name and terms, or **right-click** it to add/remove your own search terms.

Spell names are gathered automatically the first time you log in each character (and whenever you learn new spells). Run `/bmi scan` any time you want to force a re-read of the current character's spellbook.

## Commands

| Command | Description |
|---|---|
| `/bmi scan` | Re-read the current character's spellbook for spell-name search terms |
| `/bmi debug` | Print search diagnostics (open the icon picker first) |

## Dependencies

- **LibNAddOn** — must be installed and enabled.

## Saved data

`BetterMacroIconsDB` (account-wide):

- **Custom search terms** you add by right-clicking icons.
- **Spell-name terms** gathered from your characters' spellbooks, stored once per class/spec and per race and shared across the account.
