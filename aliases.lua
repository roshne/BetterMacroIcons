---@class BetterMacroIcons
---@field AliasTermsFor fun(fileID: integer, name?: string): string
---@field onIconRightClick fun(owner: table, fileID: integer)
local ns = select(2, ...)

-- aliases.lua — curated, user-defined search terms.
--
-- Right-click any icon in the macro picker to tag it with a word or phrase, then find it
-- later by that term. Aliases are account-wide (curated vocabulary should follow you to every
-- character) and keyed by icon name for patch-stability. The rest of the addon reads one seam,
-- ns.AliasTermsFor; core.lua wires the right-click into ns.onIconRightClick.

-- Seed the account DB. Non-destructive: only adds keys, never removes. Called by LibNAddOn's
-- setupDB on a version mismatch (a fresh DB has version == nil, so this seeds from scratch).
function ns:MigrateDB()
    local db = self.db
    db.aliases = db.aliases or {}
    db.version = 1
end

-- Alias key for an icon: its lowercase name (stable across patches), or a fileID fallback for
-- icons absent from the bundled name list. name is supplied by callers that already resolved it.
local function keyFor(fileID, name)
    name = name or (ns.IconName and ns.IconName(fileID)) or ""
    if name ~= "" then return name end
    return "fileid:" .. fileID
end

-- The seam the search index reads: this icon's curated terms, space-joined (or "").
function ns.AliasTermsFor(fileID, name)
    local aliases = ns.db and ns.db.aliases
    local terms = aliases and aliases[keyFor(fileID, name)]
    return terms and table.concat(terms, " ") or ""
end

local function addTerm(key, text)
    text = (text or ""):gsub("^%s+", ""):gsub("%s+$", ""):lower()
    if text == "" then return end
    local aliases = ns.db.aliases
    local terms = aliases[key] or {}
    aliases[key] = terms
    for _, t in ipairs(terms) do
        if t == text then return end  -- already present
    end
    terms[#terms + 1] = text
    if ns.refreshSearch then ns.refreshSearch() end
end

local function removeTerm(key, text)
    local aliases = ns.db and ns.db.aliases
    local terms = aliases and aliases[key]
    if not terms then return end
    for i, t in ipairs(terms) do
        if t == text then
            table.remove(terms, i)
            break
        end
    end
    if #terms == 0 then aliases[key] = nil end
    if ns.refreshSearch then ns.refreshSearch() end
end

-- The dialog's key is passed through as `data` (set via StaticPopup_Show's 4th arg). In WoW
-- 12.0's GameDialog the edit box is reached through dialog:GetEditBox() (the old self.editBox
-- field is gone).
StaticPopupDialogs["BMI_ADD_TERM"] = {
    text = "Add a search term for \"%s\":",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    OnAccept = function(dialog, data)
        addTerm(data, dialog:GetEditBox():GetText())
    end,
    EditBoxOnEnterPressed = function(editBox, data)
        addTerm(data, editBox:GetText())
        editBox:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(editBox)
        editBox:GetParent():Hide()
    end,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
}

-- Right-click menu on a grid icon: add a term, or remove one of the icon's existing terms.
function ns.onIconRightClick(owner, fileID)
    if not fileID then return end
    local name = (ns.IconName and ns.IconName(fileID)) or ""
    local display = name ~= "" and name or ("fileID " .. fileID)
    local key = keyFor(fileID, name)
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle(display)
        root:CreateButton("Add search term…", function()
            StaticPopup_Show("BMI_ADD_TERM", display, nil, key)
        end)
        local terms = ns.db and ns.db.aliases and ns.db.aliases[key]
        if terms and #terms > 0 then
            local remove = root:CreateButton("Remove term")
            for _, t in ipairs(terms) do
                remove:CreateButton(t, function() removeTerm(key, t) end)
            end
        end
    end)
end
