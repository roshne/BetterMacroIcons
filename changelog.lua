---@class BetterMacroIcons
local ns = select(2, ...)

-- In-game changelog (newest first), shown via the "Changelog" button in this
-- addon's settings. Appended automatically at release by addon-ci's release.yml
-- from the same conventional-commit grouping used for the GitHub / CurseForge
-- release notes.
---@type { version: string, notes: string }[]
ns.changelog = {
  { version = "12.0.7-r0", notes = [==[
Initial release.

### Highlights
- Search and filter the macro, transmog outfit, equipment-set, and guild-bank icon pickers
- Icon-name aliases so intuitive terms find the matching icon
- /bmi commands for scanning coverage, exporting, and cleanup
]==] },
}
