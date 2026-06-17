---@class BetterMacroIcons: AddOn
local ns = LibNAddOn(...)

local injected    = false
local fileIDMap   = {}  -- fileID integer → lowercase icon name (built once per session)
local nameIndex   = {}  -- [providerIndex] = searchable name string
local filteredMap = {}  -- [displayIndex]  = providerIndex
local searchText  = ""

local SEARCH_H = 26

-- Resolve the bundled Interface\Icons name list (ns.iconNames) to fileIDs so the
-- provider's integer-fileID entries become text-searchable. GetMacroIcons returns bare
-- fileIDs in 12.0, so the picker exposes no names of its own; GetFileIDFromPath maps each
-- bundled name back to the same fileID GetIconByIndex returns. Built once per session —
-- the icon set is stable for the lifetime of the client.
local function buildFileIDMap()
    if next(fileIDMap) then return end
    for _, name in ipairs(ns.iconNames) do
        local id = GetFileIDFromPath("Interface/Icons/" .. name)
        if id and id > 0 then
            fileIDMap[id] = name
        end
    end
end

-- Return a searchable name for a texture value returned by GetIconByIndex.
-- String: strip "INTERFACE\ICONS\" prefix → plain icon name.
-- Integer fileID: look up the bundled-name map.
local function iconName(tex)
    if not tex then return "" end
    if type(tex) == "number" then
        return fileIDMap[tex] or ""
    end
    local base = tex:match("[^/\\]+$") or tex
    return (base:gsub("%.[^%.]+$", "")):lower()
end

-- Tooltip on each grid icon showing its texture path. The IconSelector drives every
-- (recycled) button through a single setup callback that receives the button and its
-- fileID; we wrap Blizzard's callback to stash the current fileID on the button and
-- attach an idempotent OnEnter/OnLeave. Reading button._bmiIcon (refreshed each setup)
-- keeps the tooltip correct as buttons are reused while scrolling/filtering.
local function tooltipOnEnter(button)
    local icon = button._bmiIcon
    if not icon then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local name = iconName(icon)
    if name ~= "" then
        GameTooltip:SetText(name)
    else
        GameTooltip:SetText("fileID " .. icon)  -- not in the bundled list (e.g. brand-new art)
    end
    GameTooltip:Show()
end

local function tooltipOnLeave()
    GameTooltip:Hide()
end

local function installTooltips(selector)
    if selector._bmiTooltips then return end
    selector._bmiTooltips = true
    local original = selector:GetSetupCallback()
    selector:SetSetupCallback(function(button, selectionIndex, icon)
        if original then original(button, selectionIndex, icon) end
        button._bmiIcon = icon
        if not button._bmiHooked then
            button._bmiHooked = true
            button:HookScript("OnEnter", tooltipOnEnter)
            button:HookScript("OnLeave", tooltipOnLeave)
        end
    end)
end

-- Rebuild the name index from the current data provider.
-- Must be called when the provider changes (OnShow, filter type change).
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

    frame:SetHeight(frame:GetHeight() + SEARCH_H)
    frame.IconSelector:ClearAllPoints()
    frame.IconSelector:SetPoint("TOPLEFT", frame, "TOPLEFT", 21, -(97 + SEARCH_H))

    local box = CreateFrame("EditBox", "BetterMacroIconsSearchBox", frame, "SearchBoxTemplate")
    box:SetSize(494, 20)
    box:SetPoint("TOPLEFT", frame, "TOPLEFT", 21, -99)
    box:SetScript("OnTextChanged", function(self)
        SearchBoxTemplate_OnTextChanged(self)
        searchText = self:GetText():lower()
        applyFilter(frame)
    end)
    frame._bmiSearchBox = box
end

ns:registerEvent("ADDON_LOADED", function(self, addonName)
    if addonName ~= "Blizzard_MacroUI" then return end

    installTooltips(MacroPopupFrame.IconSelector)

    MacroPopupFrame:HookScript("OnShow", function(frame)
        injectSearchBox(frame)
        frame._bmiSearchBox:SetText("")
        searchText = ""
        buildFileIDMap()
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)

    hooksecurefunc(MacroPopupFrame, "SetIconFilterInternal", function(frame)
        rebuildNameIndex(frame)
        applyFilter(frame)
    end)

    -- Re-apply after Blizzard's Update() so it doesn't clobber our filtered provider.
    hooksecurefunc(MacroPopupFrame, "Update", function(frame)
        if searchText == "" then return end
        applyFilter(frame)
    end)
end)

ns:registerCommand("debug", nil, function()
    local mapCount = 0
    for _ in pairs(fileIDMap) do mapCount = mapCount + 1 end
    ns:Print("fileIDMap: " .. mapCount .. " entries")

    local total, named = #nameIndex, 0
    for _, v in ipairs(nameIndex) do
        if v ~= "" then named = named + 1 end
    end
    ns:Print("nameIndex: " .. named .. " named / " .. total .. " total")

    if MacroPopupFrame and MacroPopupFrame.iconDataProvider then
        local p = MacroPopupFrame.iconDataProvider
        ns:Print("provider total: " .. p:GetNumIcons())
        local icon2 = p:GetIconByIndex(2)
        ns:Print("GetIconByIndex(2): " .. type(icon2) .. " = " .. tostring(icon2))
    else
        ns:Print("open the icon popup first")
    end
end, "Print search diagnostics")
