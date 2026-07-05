---@class BetterMacroIcons: AddOn
local ns = LibNAddOn(...)

local injected      = false
local fileIDMap     = {}  -- fileID integer → lowercase icon name (built once per session)
local nameIndex     = {}  -- [providerIndex] = searchable name string
local filteredMap   = {}  -- [displayIndex]  = providerIndex
local searchText    = ""
local prevSearch          -- search string filteredMap currently reflects; nil forces a full scan
local SEARCH_DEBOUNCE = 100  -- ms to coalesce keystrokes before filtering

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

-- Exposed so the term modules (scan.lua / aliases.lua) can key by icon name.
---@class BetterMacroIcons
---@field IconName fun(tex: string|integer): string
---@field refreshSearch fun()
---@field ShowReport fun(title: string, lines: string[])
ns.IconName = iconName

-- Tooltip on each grid icon showing its texture path. The IconSelector drives every
-- (recycled) button through a single setup callback that receives the button and its
-- fileID; we wrap Blizzard's callback to stash the current fileID on the button and
-- attach an idempotent OnEnter/OnLeave. Reading button._bmiIcon (refreshed each setup)
-- keeps the tooltip correct as buttons are reused while scrolling/filtering.
-- Trimmed extra-terms line from a seam, or "" when the module is absent / has nothing.
local function trimmed(s)
    return (s or ""):gsub("^%s+", ""):gsub("%s+$", "")
end

local function tooltipOnEnter(button)
    local icon = button._bmiIcon
    if not icon then return end
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    local name = iconName(icon)
    GameTooltip:SetText(name ~= "" and name or ("fileID " .. icon))  -- fileID: not in the bundled list

    -- Show WHY the icon matched: its known spell name(s) and any curated aliases. Both are
    -- optional modules, so guard the seams — absent module simply omits the line.
    local spells = trimmed(ns.SpellTermsFor and ns.SpellTermsFor(icon))
    if spells ~= "" then
        GameTooltip:AddLine("Spells: " .. spells, 0.6, 0.6, 0.6, true)
    end
    local aliases = trimmed(ns.AliasTermsFor and ns.AliasTermsFor(icon, name))
    if aliases ~= "" then
        GameTooltip:AddLine("Aliases: " .. aliases, 0.6, 0.6, 0.6, true)
    end
    GameTooltip:Show()
end

local function tooltipOnLeave()
    GameTooltip:Hide()
end

-- Per (recycled) grid button: keep _bmiIcon current, and attach the hover tooltip plus a
-- right-click handler (add/manage curated search terms). OnMouseUp is used rather than
-- RegisterForClicks so Blizzard's left-click selection is left untouched.
local function installButtonHandlers(selector)
    if selector._bmiHandlers then return end
    selector._bmiHandlers = true
    local original = selector:GetSetupCallback()
    selector:SetSetupCallback(function(button, selectionIndex, icon)
        if original then original(button, selectionIndex, icon) end
        button._bmiIcon = icon
        if not button._bmiHooked then
            button._bmiHooked = true
            button:HookScript("OnEnter", tooltipOnEnter)
            button:HookScript("OnLeave", tooltipOnLeave)
            button:HookScript("OnMouseUp", function(self, mouseButton)
                if mouseButton == "RightButton" and ns.onIconRightClick then
                    ns.onIconRightClick(self, self._bmiIcon)
                end
            end)
        end
    end)
end

-- Rebuild the name index from the current data provider.
-- Must be called when the provider changes (OnShow, filter type change).
-- Whitespace tokens of the current query, rebuilt per filter pass (shared scratch table).
local searchTokens = {}
local function tokenize(str)
    wipe(searchTokens)
    for tok in str:gmatch("%S+") do
        searchTokens[#searchTokens + 1] = tok
    end
    return searchTokens
end

-- Multi-token AND: the entry matches only if it contains every token (order-independent).
local function matchesAll(name, tokens)
    for _, t in ipairs(tokens) do
        if not name:find(t, 1, true) then return false end
    end
    return true
end

local function rebuildNameIndex(frame)
    local p = frame.iconDataProvider
    wipe(nameIndex)
    for i = 1, p:GetNumIcons() do
        local tex = p:GetIconByIndex(i)
        local name = iconName(tex)
        -- Fold in the optional term modules' searchable text (spell names + curated aliases).
        -- Guarded so either module can be absent; search is plain substring over the blob.
        local extra = ((ns.SpellTermsFor and ns.SpellTermsFor(tex)) or "")
            .. " " .. ((ns.AliasTermsFor and ns.AliasTermsFor(tex, name)) or "")
        nameIndex[i] = name .. " " .. extra
    end
    prevSearch = nil  -- provider/index changed: the next filter must do a full scan
end

local function applyFilter(frame)
    local p = frame.iconDataProvider

    if searchText == "" then
        wipe(filteredMap)
        for i = 1, p:GetNumIcons() do
            filteredMap[i] = i
        end
    elseif prevSearch and prevSearch ~= "" and searchText:find(prevSearch, 1, true) == 1 then
        -- The new query is a string-prefix extension of the previous one, so each token's
        -- requirement only tightened — its matches are a subset of the current filteredMap.
        -- Narrow it in place instead of rescanning the whole index.
        local tokens = tokenize(searchText)
        local n = 0
        for _, providerIdx in ipairs(filteredMap) do
            if matchesAll(nameIndex[providerIdx], tokens) then
                n = n + 1
                filteredMap[n] = providerIdx
            end
        end
        for i = #filteredMap, n + 1, -1 do filteredMap[i] = nil end
    else
        local tokens = tokenize(searchText)
        wipe(filteredMap)
        for i, name in ipairs(nameIndex) do
            if matchesAll(name, tokens) then
                filteredMap[#filteredMap + 1] = i
            end
        end
    end
    prevSearch = searchText

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
        -- Debounce: coalesce rapid keystrokes so we don't rescan the whole name index
        -- on every key. ns:delay keeps a single pending timer (one search box), so a
        -- new keystroke replaces the pending filter. The timer fires off the addon's
        -- always-present frame, so guard against the popup being closed inside the debounce
        -- window (the released iconDataProvider lingers on the hidden frame).
        ns:delay(SEARCH_DEBOUNCE, function()
            if not frame:IsShown() or not frame.iconDataProvider then return end
            applyFilter(frame)
        end)
    end)
    frame._bmiSearchBox = box
end

-- Re-index and re-filter the live picker after the term data changes (a scan finished, an
-- alias was added/removed). No-op when the picker isn't open. Exposed to scan.lua/aliases.lua.
function ns.refreshSearch()
    if MacroPopupFrame and MacroPopupFrame:IsShown() then
        rebuildNameIndex(MacroPopupFrame)
        applyFilter(MacroPopupFrame)
    end
end

-- Show a multi-line report in LibNUI's shared copy window (the selectable/copyable `/wdebug`
-- widget) when LibNUI is installed, else print it to chat. Used by /bmi debug and /bmi coverage.
function ns.ShowReport(title, lines)
    if LibNUI and LibNUI.ShowCopyWindow then
        LibNUI.ShowCopyWindow(title, table.concat(lines, "\n"))
    else
        for _, line in ipairs(lines) do ns:Print(line) end
    end
end

ns:registerEvent("ADDON_LOADED", function(self, addonName)
    if addonName ~= "Blizzard_MacroUI" then return end

    installButtonHandlers(MacroPopupFrame.IconSelector)

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

-- Open the macro icon picker directly, so you can search icons without walking through the
-- macro editor. Uses "New" mode (it doesn't dereference a selected macro, unlike "Edit"); the
-- picker only creates a macro if you click Okay, so Cancel just backs out after browsing.
ns:registerCommand("open", nil, function()
    if InCombatLockdown() then
        ns:Print("can't open the macro UI in combat")
        return
    end
    if not C_AddOns.IsAddOnLoaded("Blizzard_MacroUI") then
        C_AddOns.LoadAddOn("Blizzard_MacroUI")
    end
    ShowUIPanel(MacroFrame)
    MacroPopupFrame.mode = IconSelectorPopupFrameModes.New
    MacroPopupFrame:Show()
end, "Open the macro icon picker to search icons")

ns:registerCommand("debug", nil, function()
    local mapCount = 0
    for _ in pairs(fileIDMap) do mapCount = mapCount + 1 end

    -- Account-wide totals from the pooled term data — stable regardless of which filter tab
    -- is open (guarded so they still read 0 if a term module is removed).
    local spellTagged = ns.SpellTermsCount and ns.SpellTermsCount() or 0
    local aliasTagged = ns.AliasCount and ns.AliasCount() or 0

    local lines = {
        "fileIDMap: " .. mapCount .. " entries",
        "nameIndex: " .. #nameIndex .. " entries",
        ("spell-tagged icons %d, alias-tagged icons %d (account-wide totals)"):format(spellTagged, aliasTagged),
    }
    -- The current filter tab only exposes a subset of icons; report its size for context.
    if MacroPopupFrame and MacroPopupFrame.iconDataProvider then
        lines[#lines + 1] = "current tab provider: " .. MacroPopupFrame.iconDataProvider:GetNumIcons() .. " icons"
    else
        lines[#lines + 1] = "current tab provider: (open the icon popup)"
    end
    ns.ShowReport("BMI Debug", lines)
end, "Print search diagnostics")
