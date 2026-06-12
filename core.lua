---@class BetterMacroIcons: AddOn
local ns = LibNAddOn(...)

local injected    = false
local nameIndex   = {}  -- [providerIndex] = lowercaseName
local filteredMap = {}  -- [displayIndex]  = providerIndex
local searchText  = ""

local SEARCH_H    = 26  -- pixels added to frame + shifted down

-- Strip path prefix and file extension, lowercase. "Interface/Icons/Spell_Frost_FrostBolt02.blp" → "spell_frost_frostbolt02"
local function iconName(tex)
    if not tex then return "" end
    local base = tex:match("[^/\\]+$") or tex
    return (base:gsub("%.[^%.]+$", "")):lower()
end

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
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)
    frame._bmiSearchBox = box
end

ns:registerEvent("ADDON_LOADED", function(self, addonName)
    if addonName ~= "Blizzard_MacroUI" then return end

    -- After OnShow: inject the search box (once), clear it, and drive the initial filter.
    -- MacroPopupFrameMixin:OnShow already set iconDataProvider and called Update() by now.
    hooksecurefunc(MacroPopupFrameMixin, "OnShow", function(frame)
        injectSearchBox(frame)
        frame._bmiSearchBox:SetText("")
        searchText = ""
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)

    -- After SetIconFilterInternal: the data provider now has a new type filter applied.
    -- Rebuild the name index and re-drive our text filter on top of it.
    -- Guard: this mixin is shared with GuildBank, Transmog, etc.
    hooksecurefunc(IconSelectorPopupFrameTemplateMixin, "SetIconFilterInternal", function(frame)
        if frame ~= MacroPopupFrame then return end
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)

    -- After Update: re-drive if search is active, so any re-Update from Blizzard
    -- code doesn't clobber our filtered provider.
    hooksecurefunc(MacroPopupFrameMixin, "Update", function(frame)
        if searchText == "" then return end
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)
end)
