---@class BetterMacroIcons
---@field SpellTermsFor fun(fileID: integer): string
---@field SpellTermsCount fun(): integer
---@field CanonRace fun(raceID: integer): integer
local ns = select(2, ...)

-- scan.lua — automatic spell-name search terms (REMOVABLE MODULE).
--
-- Scans the player's spellbook and maps each spell's icon fileID to the spell's name, so
-- icons become findable by spell name in the macro picker. The store is keyed by spec
-- (class/spec spells) and by race (racials + general spells) — never by character — so each
-- spec/race is captured once and pooled account-wide. The rest of the addon reads exactly
-- one seam, ns.SpellTermsFor; delete this file (and its .toc line) and everything else keeps
-- working, just without spell terms. The orphaned DB sub-tables simply linger harmlessly.

local SCAN_DEBOUNCE = 300  -- ms to coalesce SPELLS_CHANGED bursts into one scan

-- Playable-race data for `/bmi coverage`, mirrored from the hand-verified suite source
-- Warbandeer_Collected/data/models.lua (its FACTIONS list + RaceAlias). BMI is a separate
-- addon so it can't read that namespace at runtime; this is a small copy. PLAYABLE_RACES is the
-- 26 canonical playable races; RACE_ALIAS collapses faction/neutral variants that share a racial
-- set onto their canonical id (Pandaren 24/26 → 25, Dracthyr 70 → 52, Earthen 85 → 84,
-- Haranir 91 → 86). Race keys are canonicalised at store time, and coverage resolves names live
-- via GetRaceInfo so an unknown/future id degrades gracefully. Haranir (both-faction, like
-- Earthen) is a Midnight race not yet in models.lua — added here from live; its two faction ids
-- (86 and 91) are both confirmed in-game. Sync back to models.lua.
local PLAYABLE_RACES = {
    1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 22, 25, 27, 28, 29, 30, 31, 32, 34, 35, 36, 37, 52, 84, 86,
}
local RACE_ALIAS = { [24] = 25, [26] = 25, [70] = 52, [85] = 84, [91] = 86 }
local function canonRace(raceID)
    return RACE_ALIAS[raceID] or raceID
end
ns.CanonRace = canonRace  -- exposed for dataset.lua (export/diff canonicalise race keys)

local mergedSpellTerms = {}  -- [fileID] = " name1 name2 " — union of every spec/race section
local scanPending

-- Lazily create the three persisted bucket tables. Owned entirely by this file, so removing
-- scan.lua removes every reference to them. Keys: spec ID / race ID / class ID →
-- { [fileID] = " names " }. bySpec = spec spells, byRace = racials (General line), byClass =
-- class-base spells + professions/utility (the Class line + any other non-spec, non-General line).
local function stores()
    local db = ns.db
    db.spellTermsBySpec = db.spellTermsBySpec or {}
    db.spellTermsByRace = db.spellTermsByRace or {}
    db.spellTermsByClass = db.spellTermsByClass or {}
    return db.spellTermsBySpec, db.spellTermsByRace, db.spellTermsByClass
end

-- Append a lowercased spell name to a bucket entry, skipping duplicates. Names are stored
-- space-delimited with a leading + trailing space, so a single :find(" name ") both searches
-- and dedupes.
local function addName(bucket, fileID, name)
    name = name:lower()
    local cur = bucket[fileID]
    if not cur then
        bucket[fileID] = " " .. name .. " "
    elseif not cur:find(" " .. name .. " ", 1, true) then
        bucket[fileID] = cur .. name .. " "
    end
end

-- Recompute the in-memory union of every spec + race + class section (deduped per icon).
local function rebuildMerged()
    wipe(mergedSpellTerms)
    local bySpec, byRace, byClass = stores()
    local function absorb(section)
        for fileID, names in pairs(section) do
            for name in names:gmatch("%S+") do
                addName(mergedSpellTerms, fileID, name)
            end
        end
    end
    local function absorbAll(t) for _, section in pairs(t) do absorb(section) end end
    absorbAll(bySpec); absorbAll(byRace); absorbAll(byClass)
    -- Fold in the baseline shipped with the addon (data/spellterms.lua), so a fresh install has
    -- coverage out of the box; live scans merge on top (deduped). Optional file — guarded.
    local bundled = ns.bundledSpellTerms
    if bundled then
        absorbAll(bundled.bySpec or {}); absorbAll(bundled.byRace or {}); absorbAll(bundled.byClass or {})
    end
end

-- Scan the Player spellbook into the spec/race/class buckets, routed by skill-line index:
-- spec lines (with a specID) → bySpec; the General line (Enum...General, racials + utility) →
-- byRace; every other non-spec line (the Class line's class-base spells, + professions) →
-- byClass. force wipes this character's own sections first (repair/refresh); otherwise it's an
-- additive merge that records only names not already present — so a fully-captured spec/race/
-- class does no meaningful work and alts contribute nothing. Returns the pooled icon count.
local function scanSpells(force)
    if not ns.db then return 0 end
    local bySpec, byRace, byClass = stores()

    local _, raceFile, raceID = UnitRace("player")
    local raceKey = raceID and canonRace(raceID) or raceFile
    local classID = select(3, UnitClass("player"))
    byRace[raceKey] = (not force and byRace[raceKey]) or {}
    if classID then byClass[classID] = (not force and byClass[classID]) or {} end

    local wipedSpec = force and {} or nil
    local general = Enum.SpellBookSkillLineIndex.General
    local bank = Enum.SpellBookSpellBank.Player
    for lineIdx = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local line = C_SpellBook.GetSpellBookSkillLineInfo(lineIdx)
        if line then
            local bucket
            local sid = line.specID
            if sid and sid > 0 then
                if wipedSpec and not wipedSpec[sid] then
                    wipedSpec[sid] = true
                    bySpec[sid] = {}
                end
                bySpec[sid] = bySpec[sid] or {}
                bucket = bySpec[sid]
            elseif lineIdx == general then
                bucket = byRace[raceKey]            -- racials + general utility
            elseif classID then
                bucket = byClass[classID]           -- class-base (Class line) + professions/misc
            end
            if bucket then
                for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                    local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
                    if info and info.iconID and info.name and info.name ~= "" then
                        addName(bucket, info.iconID, info.name)
                    end
                end
            end
        end
    end

    rebuildMerged()
    local count = 0
    for _ in pairs(mergedSpellTerms) do count = count + 1 end
    return count
end

-- The one symbol the rest of the addon reads: pooled spell names for an icon (or "").
function ns.SpellTermsFor(fileID)
    return mergedSpellTerms[fileID] or ""
end

-- Diagnostic (/bmi debug): how many icons carry pooled spell terms — a stable account-wide
-- total, independent of the current filter tab.
function ns.SpellTermsCount()
    local n = 0
    for _ in pairs(mergedSpellTerms) do n = n + 1 end
    return n
end

-- Coalesce SPELLS_CHANGED bursts into a single additive scan. Uses ns:after (not ns:delay)
-- so it can't clobber core's single-slot keystroke-debounce timer.
local function queueScan()
    if scanPending then return end
    scanPending = true
    ns:after(SCAN_DEBOUNCE, function()
        scanPending = false
        scanSpells(false)
        if ns.refreshSearch then ns.refreshSearch() end
    end)
end

ns:registerEvent("ADDON_LOADED", function(_, addonName)
    if addonName ~= ns._NAME then return end
    stores()         -- ensure buckets exist
    rebuildMerged()  -- search works immediately from persisted data, before the first scan
end)

ns:registerEvent("SPELLS_CHANGED", queueScan)

ns:registerCommand("scan", nil, function()
    local count = scanSpells(true)
    if ns.refreshSearch then ns.refreshSearch() end
    ns:Print(("scanned spellbook — %d icons now carry spell names"):format(count))
end, "Rescan your spellbook for spell-name search terms")

-- Wipe the racial + class-base stores (keeps the spec store, which is always correctly bucketed)
-- so they rebuild cleanly — e.g. after a bucketing fix. Re-log or /bmi scan each character to refill.
ns:registerCommand("reset", nil, function()
    if ns.db then
        ns.db.spellTermsByRace = {}
        ns.db.spellTermsByClass = {}
    end
    rebuildMerged()
    if ns.refreshSearch then ns.refreshSearch() end
    ns:Print("cleared racial + class-base terms (spec terms kept) — re-log or /bmi scan each character to rebuild")
end, "Wipe racial/class-base terms so they rebuild cleanly (keeps spec terms)")

-- Report which class/specs and races have been captured — the gaps to fill by logging into
-- alts, en route to a complete bundled dataset. Specs are enumerated authoritatively from the
-- API (real spec IDs to match the store keys); races compare captured keys to PLAYABLE_RACES.
ns:registerCommand("coverage", nil, function()
    local bySpec, byRace = stores()
    -- A spec/race counts as covered if either the live scan or the shipped baseline has it.
    local bundled = ns.bundledSpellTerms or {}
    local bunSpec, bunRace = bundled.bySpec or {}, bundled.byRace or {}

    local specTotal, specHave, missingSpecs = 0, 0, {}
    for ci = 1, GetNumClasses() do
        local className, _, classID = GetClassInfo(ci)
        local missing = {}
        for si = 1, C_SpecializationInfo.GetNumSpecializationsForClassID(classID) do
            local specID, specName = GetSpecializationInfoForClassID(classID, si)
            if specID then
                specTotal = specTotal + 1
                if bySpec[specID] or bunSpec[specID] then
                    specHave = specHave + 1
                else
                    missing[#missing + 1] = specName
                end
            end
        end
        if #missing > 0 then
            missingSpecs[#missingSpecs + 1] = className .. ": " .. table.concat(missing, ", ")
        end
    end

    local raceTotal, raceHave, missingRaces, playable = 0, 0, {}, {}
    for _, id in ipairs(PLAYABLE_RACES) do
        playable[id] = true
        local info = C_CreatureInfo.GetRaceInfo(id)
        if info then  -- recognised by this client (unknown/future ids drop out)
            raceTotal = raceTotal + 1
            if byRace[id] or bunRace[id] then raceHave = raceHave + 1 else missingRaces[#missingRaces + 1] = info.raceName end
        end
    end

    -- Captured races absent from PLAYABLE_RACES — surfaced so the bundled list can be updated.
    local untracked = {}
    for id in pairs(byRace) do
        local canon = type(id) == "number" and canonRace(id) or id
        if not playable[canon] then
            local info = type(canon) == "number" and C_CreatureInfo.GetRaceInfo(canon)
            untracked[#untracked + 1] = (info and info.raceName or tostring(canon)) .. " (" .. tostring(id) .. ")"
        end
    end

    local lines = { ("coverage — specs %d/%d, races %d/%d"):format(specHave, specTotal, raceHave, raceTotal) }
    if #missingSpecs > 0 then
        lines[#lines + 1] = "missing specs:"
        for _, line in ipairs(missingSpecs) do lines[#lines + 1] = "  " .. line end
    end
    if #missingRaces > 0 then
        lines[#lines + 1] = "missing races: " .. table.concat(missingRaces, ", ")
    end
    if #untracked > 0 then
        lines[#lines + 1] = "captured but not in race list: " .. table.concat(untracked, ", ")
    end
    if #missingSpecs == 0 and #missingRaces == 0 then
        lines[#lines + 1] = "all class/specs and races captured — ready to bundle!"
    end

    ns.ShowReport("BMI Coverage", lines)
end, "Show which class/specs and races still need capturing")
