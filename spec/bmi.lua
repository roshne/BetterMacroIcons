-- spec/bmi.lua — busted loader for BetterMacroIcons source files. Not a test file itself: busted
-- only collects *_spec.lua, so this is pulled in with require("spec.bmi").
--
-- assert(loadfile(f))(addonName, ns) reproduces exactly how WoW runs an addon file, supplying the
-- `...` vararg each file reads back via `local ns = select(2, ...)`.
--
-- dataset.lua registers its two slash commands at load time and touches nothing else until one of
-- them runs, so the namespace below only needs the seams /bmi export and /bmi diff actually read:
-- the three live stores, the bundled baseline, ns.CanonRace and ns.ShowReport.

local M = {}

-- The faction/neutral variant folding that scan.lua exposes as ns.CanonRace. It is pure Lua, so
-- mirroring it is cheaper than loading scan.lua (which would drag in the whole spellbook API).
local RACE_ALIAS = { [24] = 25, [26] = 25, [70] = 52, [85] = 84, [91] = 86 }

-- Load dataset.lua against a fresh namespace. `live` and `bundled` are optional
-- { bySpec = ..., byRace = ..., byClass = ... } tables. Returns a harness exposing
-- h.export() / h.diff(), each returning the report lines that command emitted.
function M.load(live, bundled)
    live = live or {}

    -- /bmi diff resolves display names only for sections it actually has something to report on.
    _G.GetSpecializationInfoByID = function(id) return id, "spec" .. id end
    _G.C_CreatureInfo = {
        GetRaceInfo = function(id) return { raceName = "race" .. id } end,
        GetClassInfo = function(id) return { className = "class" .. id } end,
    }

    local h, commands = {}, {}
    local ns = {
        db = {
            spellTermsBySpec = live.bySpec or {},
            spellTermsByRace = live.byRace or {},
            spellTermsByClass = live.byClass or {},
        },
        bundledSpellTerms = bundled,
        CanonRace = function(raceID) return RACE_ALIAS[raceID] or raceID end,
        ShowReport = function(title, lines) h.title, h.lines = title, lines end,
    }
    -- Load-time colon call: ns:registerCommand(name, subcommand, handler, description). Keep the
    -- handler so a test can run the command directly — there is no slash dispatcher here.
    ns.registerCommand = function(_self, name, _sub, fn) commands[name] = fn end

    assert(loadfile("dataset.lua"))("BetterMacroIcons", ns)

    h.ns = ns
    h.export = function() commands.export() return h.lines end
    h.diff = function() commands.diff() return h.lines end
    return h
end

-- Load an emitted /bmi export back into a table, so a test can assert on the round trip the same
-- way the addon consumes data/spellterms.lua.
function M.parse(lines)
    local ns = {}
    assert(loadstring(table.concat(lines, "\n")))("BetterMacroIcons", ns)
    return ns.bundledSpellTerms
end

return M
