---@class BetterMacroIcons: AddOn
local ns = LibNAddOn(...)

local injected    = false
local fileIDMap   = {}  -- fileID integer → lowercase icon name (for 10.0+ fileID-only icons)
local nameIndex   = {}  -- [providerIndex] = searchable name string
local filteredMap = {}  -- [displayIndex]  = providerIndex
local searchText  = ""

local SEARCH_H = 26

-- Call the same C functions the macro picker uses; non-numeric entries are plain icon
-- names ("spell_frost_frostbolt02").  GetFileIDFromPath maps each one back to its integer
-- fileDataID so we can match when GetIconByIndex returns a bare integer (10.0+ icons).
-- Built once per session — the icon set is stable for the lifetime of the client.
local function buildFileIDMap()
    if next(fileIDMap) then return end
    local t = {}
    GetLooseMacroIcons(t)
    GetMacroIcons(t)
    GetLooseMacroItemIcons(t)
    GetMacroItemIcons(t)
    for _, s in ipairs(t) do
        if not tonumber(s) then
            local id = GetFileIDFromPath("Interface/Icons/" .. s)
            if id and id > 0 then
                fileIDMap[id] = s:lower()
            end
        end
    end
end

-- Return a searchable name for a texture value returned by GetIconByIndex.
-- String: strip "INTERFACE\ICONS\" prefix and extension → plain icon name.
-- Integer fileID: look up the name we pre-built from the raw icon list.
local function iconName(tex)
    if not tex then return "" end
    if type(tex) == "number" then
        return fileIDMap[tex] or ""
    end
    local base = tex:match("[^/\\]+$") or tex
    return (base:gsub("%.[^%.]+$", "")):lower()
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
        buildFileIDMap()
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
