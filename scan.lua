---@class BetterMacroIcons
---@field SpellTermsFor fun(fileID: integer): string
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

local mergedSpellTerms = {}  -- [fileID] = " name1 name2 " — union of every spec/race section
local scanPending

-- Lazily create the two persisted bucket tables. Owned entirely by this file, so removing
-- scan.lua removes every reference to them. Keys: spec ID / race ID → { [fileID] = " names " }.
local function stores()
    local db = ns.db
    db.spellTermsBySpec = db.spellTermsBySpec or {}
    db.spellTermsByRace = db.spellTermsByRace or {}
    return db.spellTermsBySpec, db.spellTermsByRace
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

-- Recompute the in-memory union of every spec + race section (deduped per icon).
local function rebuildMerged()
    wipe(mergedSpellTerms)
    local bySpec, byRace = stores()
    local function absorb(section)
        for fileID, names in pairs(section) do
            for name in names:gmatch("%S+") do
                addName(mergedSpellTerms, fileID, name)
            end
        end
    end
    for _, section in pairs(bySpec) do absorb(section) end
    for _, section in pairs(byRace) do absorb(section) end
end

-- Scan the Player spellbook into the spec/race buckets. Each skill line's spells go to the
-- spec bucket for its specID, or the race bucket when the line has no spec (the General line:
-- racials + class-base). force wipes this character's own sections first (repair/refresh);
-- otherwise it's an additive merge that records only names not already present — so a
-- fully-captured spec/race does no meaningful work and alts contribute nothing. Returns the
-- pooled icon count.
local function scanSpells(force)
    if not ns.db then return 0 end
    local bySpec, byRace = stores()

    local _, raceFile, raceID = UnitRace("player")
    local raceKey = raceID or raceFile
    byRace[raceKey] = (not force and byRace[raceKey]) or {}

    local wipedSpec = force and {} or nil
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
            else
                bucket = byRace[raceKey]
            end
            for i = line.itemIndexOffset + 1, line.itemIndexOffset + line.numSpellBookItems do
                local info = C_SpellBook.GetSpellBookItemInfo(i, bank)
                if info and info.iconID and info.name and info.name ~= "" then
                    addName(bucket, info.iconID, info.name)
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
