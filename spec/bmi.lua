-- spec/bmi.lua — busted loader for BetterMacroIcons source files. Not a test file itself: busted
-- only collects *_spec.lua, so this is pulled in with require("spec.bmi").
--
-- assert(loadfile(f))(addonName, ns) reproduces exactly how WoW runs an addon file, supplying the
-- `...` vararg each file reads back via `local ns = select(2, ...)`.
--
-- Two loaders, picked by how much of the addon a spec needs:
--
--   M.load(live, bundled)  dataset.lua alone, against hand-built stores. Its two slash commands
--                          are registered at load time and touch nothing else until one runs, so
--                          the namespace only needs what /bmi export and /bmi diff read: the
--                          three live stores, the bundled baseline, ns.CanonRace, ns.ShowReport.
--   M.session(opts)        the whole term pipeline — data/spellterms.lua (the REAL shipped
--                          baseline), scan.lua and dataset.lua over one SavedVariables table,
--                          plus the event, command and spellbook plumbing a login needs.
--
-- core.lua is picker/frame code either way, and stays in-game-tested; the seams it would provide
-- (ShowReport, refreshSearch) are stubbed here instead.

local M = {}

-- The faction/neutral variant folding that scan.lua exposes as ns.CanonRace. It is pure Lua, so
-- mirroring it is cheaper than loading scan.lua (which would drag in the whole spellbook API).
local RACE_ALIAS = { [24] = 25, [26] = 25, [70] = 52, [85] = 84, [91] = 86 }

-- Spec/race/class display-name resolvers. /bmi coverage and /bmi diff reach for these only when
-- a section has something to report, and ids are echoed so a test can assert on a label without
-- hard-coding client strings. Shared by both loaders so the two never drift.
local function installNameStubs()
    _G.GetSpecializationInfoByID = function(id) return id, "spec" .. id end
    _G.C_CreatureInfo = {
        GetRaceInfo = function(id) return { raceName = "race" .. id } end,
        GetClassInfo = function(id) return { className = "class" .. id } end,
    }
end

-- Load dataset.lua against a fresh namespace. `live` and `bundled` are optional
-- { bySpec = ..., byRace = ..., byClass = ... } tables. Returns a harness exposing
-- h.export() / h.diff(), each returning the report lines that command emitted.
function M.load(live, bundled)
    live = live or {}
    installNameStubs()

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

-- ---------------------------------------------------------------------------------------------
-- M.session — the whole term pipeline over one SavedVariables table.

-- .toc order for the files a session loads. data/spellterms.lua only sets a field, but it has to
-- precede scan.lua so rebuildMerged sees the baseline, exactly as in game.
local SESSION_FILES = { "data/spellterms.lua", "scan.lua", "dataset.lua" }

-- loadfile once per file, call once per namespace: a chunk's locals are created fresh on every
-- call, so reusing the compiled chunk keeps sessions isolated while parsing the 50 KB baseline
-- only once for the whole run.
local chunks = {}
local function chunkFor(path)
    chunks[path] = chunks[path] or assert(loadfile(path))
    return chunks[path]
end

-- The character the spellbook stubs answer for. Module-level because the stubs are globals: one
-- session is live at a time, and every M.session() rebinds this.
local character = { raceID = 1, raceFile = "race1", classID = 1, classFile = "class1", lines = {} }

-- Flatten a spellbook fixture into lines carrying the cumulative itemIndexOffset the real API
-- reports, so slot numbers are unique across lines exactly as in game. Fixture shape is ordered,
-- mirroring C_SpellBook.GetNumSpellBookSkillLines — index 1 is the General line, index 2 the
-- Class line, and any line with a specID is a spec line:
--   { { spells = { { fileID, "Spell Name" } } }, { specID = 250, spells = { ... } } }
local function buildLines(spellbook)
    local lines, offset = {}, 0
    for _, line in ipairs(spellbook or {}) do
        local spells = line.spells or {}
        lines[#lines + 1] = { specID = line.specID, offset = offset, spells = spells }
        offset = offset + #spells
    end
    return lines
end

-- The globals scan.lua drives, all answering from `character`, so a spec describes a character
-- rather than poking _G.
local function installSpellbookStubs()
    _G.wipe = function(t)
        for k in pairs(t) do t[k] = nil end
        return t
    end
    _G.Enum = {
        SpellBookSkillLineIndex = { General = 1 },
        SpellBookSpellBank = { Player = 1 },
    }
    -- UnitRace/UnitClass return (localized, file, id); scan.lua reads the 2nd and 3rd.
    _G.UnitRace = function() return character.raceFile, character.raceFile, character.raceID end
    _G.UnitClass = function() return character.classFile, character.classFile, character.classID end
    _G.C_SpellBook = {
        GetNumSpellBookSkillLines = function() return #character.lines end,
        GetSpellBookSkillLineInfo = function(idx)
            local line = character.lines[idx]
            if not line then return nil end
            return { specID = line.specID, itemIndexOffset = line.offset, numSpellBookItems = #line.spells }
        end,
        GetSpellBookItemInfo = function(slot)
            for _, line in ipairs(character.lines) do
                local i = slot - line.offset
                if i >= 1 and i <= #line.spells then
                    return { iconID = line.spells[i][1], name = line.spells[i][2] }
                end
            end
            return nil
        end,
    }
end

---Load the baseline + scan.lua + dataset.lua against one namespace and SavedVariables table.
---@param opts table? { db = table?, race = integer?, class = integer?, spellbook = table? }
---@return table harness ns/db plus fire, login, run, setSpellbook and the captured output
function M.session(opts)
    opts = opts or {}
    installNameStubs()
    installSpellbookStubs()
    character.raceID = opts.race or 1
    character.raceFile = "race" .. character.raceID
    character.classID = opts.class or 1
    character.classFile = "class" .. character.classID
    character.lines = buildLines(opts.spellbook)

    local h = { reports = {}, prints = {}, refreshes = 0, timers = {} }
    local commands, events = {}, {}

    -- LibNAddOn's setupDB links ns.db from an ADDON_LOADED handler registered ahead of every
    -- other one, so scan.lua's handler always sees a live DB — modelled by linking it up front.
    local ns = { _NAME = "BetterMacroIcons", db = opts.db or {} }

    function ns:registerEvent(name, handler, idx)
        local list = events[name] or {}
        events[name] = list
        if idx then table.insert(list, idx, handler) else list[#list + 1] = handler end
    end

    function ns:registerCommand(cmd, subcmd, handler)
        commands[subcmd and (cmd .. " " .. subcmd) or cmd] = handler
    end

    function ns:Print(msg) h.prints[#h.prints + 1] = msg end

    -- Timers are captured rather than run, so a spec drives the debounced scan deterministically.
    function ns:after(_, fn) h.timers[#h.timers + 1] = fn end

    ns.ShowReport = function(title, lines) h.reports[#h.reports + 1] = { title = title, lines = lines } end
    ns.refreshSearch = function() h.refreshes = h.refreshes + 1 end

    for _, path in ipairs(SESSION_FILES) do chunkFor(path)("BetterMacroIcons", ns) end

    h.ns = ns
    h.db = ns.db

    ---Fire an event the way LibNAddOn's listener does: every handler, in registration order.
    function h.fire(event, ...)
        for _, handler in ipairs(events[event] or {}) do handler(ns, ...) end
    end

    ---The login path: ADDON_LOADED for this addon (seed stores, migrate, rebuild merged).
    function h.login() h.fire("ADDON_LOADED", "BetterMacroIcons") end

    ---Invoke a registered slash command by name ("scan", "reset", "diff", "export", "coverage").
    function h.run(name)
        local handler = assert(commands[name], "no such command: " .. tostring(name))
        handler(ns, "")
    end

    ---Swap the stubbed spellbook mid-session (e.g. to log in as a second character).
    function h.setSpellbook(spellbook) character.lines = buildLines(spellbook) end

    ---The most recent ShowReport call, as { title = ..., lines = { ... } }.
    function h.lastReport() return h.reports[#h.reports] end

    ---Run every pending ns:after callback (the SPELLS_CHANGED debounce).
    function h.flushTimers()
        local pending = h.timers
        h.timers = {}
        for _, fn in ipairs(pending) do fn() end
    end

    return h
end

return M
