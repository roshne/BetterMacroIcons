---@class BetterMacroIcons: AddOn
local ns = LibNAddOn(...)

local injected     = false
local spellNameMap = {}  -- fileID → lowercase spell name(s) for icon name lookup
local nameIndex    = {}  -- [providerIndex] = searchable name string
local filteredMap  = {}  -- [displayIndex]  = providerIndex
local searchText   = ""

local SEARCH_H = 26  -- pixels added to frame height + shifted down

-- Build fileID → spell name mapping from the character's spellbook.
-- In WoW 10.0+ GetIconByIndex returns integer fileIDs, not path strings.
-- Spell names are the only human-readable handle we have for those IDs.
local function buildSpellNameMap()
    wipe(spellNameMap)
    if not (C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines) then return end
    for idx = 1, C_SpellBook.GetNumSpellBookSkillLines() do
        local info = C_SpellBook.GetSpellBookSkillLineInfo(idx)
        if info then
            for i = 1, info.numSpellBookItems do
                local si = info.itemIndexOffset + i
                local spellType, id = C_SpellBook.GetSpellBookItemType(si, Enum.SpellBookSpellBank.Player)
                if spellType ~= Enum.SpellBookItemType.Flyout and id then
                    local tex  = C_SpellBook.GetSpellBookItemTexture(si, Enum.SpellBookSpellBank.Player)
                    local name = tex and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
                    if tex and name then
                        local lower = name:lower()
                        spellNameMap[tex] = spellNameMap[tex] and (spellNameMap[tex] .. " " .. lower) or lower
                    end
                end
            end
        end
    end
end

-- Return a searchable name for a texture value.
-- Pre-10.0: string path "Interface/Icons/Spell_Frost_FrostBolt02.blp" → "spell_frost_frostbolt02"
-- 10.0+: integer fileID → spell name from spellNameMap, or "" if unknown
local function iconName(tex)
    if not tex then return "" end
    if type(tex) == "string" then
        local base = tex:match("[^/\\]+$") or tex
        return (base:gsub("%.[^%.]+$", "")):lower()
    end
    return spellNameMap[tex] or ""
end

-- Rebuild the name index from the current data provider.
-- Must be called when the provider changes (OnShow, filter type change).
-- Not called on every keystroke — applyFilter reuses the existing index.
local function rebuildNameIndex(frame)
    local p = frame.iconDataProvider
    wipe(nameIndex)
    for i = 1, p:GetNumIcons() do
        nameIndex[i] = iconName(p:GetIconByIndex(i))
    end
end

local function applyFilter(frame)
    local p = frame.iconDataProvider
    wipe(filteredMap)
    if searchText == "" then
        for i = 1, p:GetNumIcons() do
            filteredMap[i] = i
        end
    else
        for i, name in ipairs(nameIndex) do
            if name:find(searchText, 1, true) then
                filteredMap[#filteredMap + 1] = i
            end
        end
    end
    frame.IconSelector:SetSelectionsDataProvider(
        function(idx) return p:GetIconByIndex(filteredMap[idx]) end,
        function()    return #filteredMap end
    )
    frame.IconSelector:UpdateSelections()
end

local function injectSearchBox(frame)
    if injected then return end
    injected = true

    -- Grow the popup and shift the icon grid down to make room for the search row.
    -- Buttons are anchored BOTTOMRIGHT inside BorderBox (setAllPoints), so they
    -- stay fixed relative to the bottom — the gap between grid and buttons is unchanged.
    frame:SetHeight(frame:GetHeight() + SEARCH_H)
    frame.IconSelector:ClearAllPoints()
    frame.IconSelector:SetPoint("TOPLEFT", frame, "TOPLEFT", 21, -(97 + SEARCH_H))

    local box = CreateFrame("EditBox", "BetterMacroIconsSearchBox", frame, "SearchBoxTemplate")
    box:SetSize(494, 20)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 21, -99)
    box:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        searchText = self:GetText():lower()
        applyFilter(frame)  -- nameIndex is already built; just re-filter
    end)
    frame._bmiSearchBox = box
end

ns:registerEvent("ADDON_LOADED", function(self, addonName)
    if addonName ~= "Blizzard_MacroUI" then return end

    -- IMPORTANT: mixin="MacroPopupFrameMixin" in XML copies all mixin methods onto the
    -- frame at creation time. Hooking the mixin table after the fact has no effect —
    -- the frame holds the original pre-hook reference. Hook the frame directly.

    hooksecurefunc(MacroPopupFrame, "OnShow", function(frame)
        injectSearchBox(frame)
        frame._bmiSearchBox:SetText("")
        searchText = ""
        buildSpellNameMap()
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)

    -- After SetIconFilterInternal the provider reflects the new type filter;
    -- rebuild the name index and re-apply our text filter on top.
    hooksecurefunc(MacroPopupFrame, "SetIconFilterInternal", function(frame)
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)

    -- After Update re-apply if search is active so any Blizzard re-Update
    -- doesn't clobber our filtered provider.
    hooksecurefunc(MacroPopupFrame, "Update", function(frame)
        if searchText == "" then return end
        applyFilter(frame)
    end)
end)
