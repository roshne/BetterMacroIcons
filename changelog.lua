---@class BetterMacroIcons
local ns = select(2, ...)

-- In-game changelog (newest first), shown via the "Changelog" button in this
-- addon's settings. Appended automatically at release by addon-ci's release.yml
-- from the same conventional-commit grouping used for the GitHub / CurseForge
-- release notes.
---@type { version: string, notes: string }[]
ns.changelog = {
  { version = "12.0.7-r4", notes = [==[
### CI
- add push-notify caller (one post per push, as Github-Repo-Updates) (roshne/Tooling#111)

]==] },
  { version = "12.0.7-r3", notes = [==[
### Documentation
- list the guild bank tab picker in Notes (#27)

]==] },
  { version = "12.0.7-r2", notes = [==[
### Features
- search box in the bank tab settings menu (default + Bagnon) (#25)

### CI
- add Discord merged-PR notification caller (addon-ci) (#24)

]==] },
  { version = "12.0.7-r1", notes = [==[
### Features
- in-game changelog viewer via LibNAddOn (#18)
- extend icon search to the equipment set and guild bank pickers (#16)
- extend icon search to the transmog outfit picker (#15)
- class-base bucket + /bmi diff + /bmi reset (#13)
- bundled spellterms baseline + /bmi export + Haranir race (#12)
- copy-window reports + /bmi open (#11)
- add /bmi cleanup to delete leaked VuhDo/Plumber macros (#10)
- spell-name + custom icon search terms, with coverage (#9)
- tooltip with icon file path on each grid icon (#2)
- full-coverage icon search via bundled name list (#1)
- inject icon search box into MacroPopupFrame

### Bug Fixes
- guard debounced filter against a closed icon popup (#14)
- handle fileID integers from iconDataProvider (WoW 10.0+)
- hook MacroPopupFrame directly, not the mixin table

### Performance
- debounce + incremental filter for the icon search (#6)

### Maintenance
- add CurseForge project ID to toc (#22)
- gitignore local dist/ build artifacts (#20)
- add Apache-2.0 LICENSE (#19)
- add .luarc.json mirroring .luacheckrc globals (#5)
- initial addon scaffold

### CI
- add release + publish caller workflows (addon-ci) (#23)
- adopt shared addon-ci lua-test workflow (#4)

### Other Changes
- Add standard docs + test CI (#3)

]==] },
  { version = "12.0.7-r0", notes = [==[
Initial release.

### Highlights
- Search and filter the macro, transmog outfit, equipment-set, and guild-bank icon pickers
- Icon-name aliases so intuitive terms find the matching icon
- /bmi commands for scanning coverage, exporting, and cleanup
]==] },
}
