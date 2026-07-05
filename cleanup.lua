---@type BetterMacroIcons
local ns = select(2, ...)

-- Removable module. Deletes the duplicate macros that VuhDo and Plumber leak.
--
-- VuhDo's "Disconnect Shield" serialises the group roster into VuhDoDCShieldData /
-- VuhDoDCShieldNames, and Plumber's Housing teleport spawns a fresh "Plumber Housing
-- Macro" (an incrementing `/click PLMRn`) — both fail to reuse their single intended
-- macro, so copies pile up across the account- and character-wide macro lists (they can
-- fill all 120 account slots and block new macros everywhere). All are pure caches:
-- VuhDo regenerates its pair on the next roster update while the shield is enabled, and
-- Plumber recreates its teleport macro the next time you drag the House button to a bar.
--
-- Delete this file + its .toc line to remove the feature; the rest of the addon is
-- unaffected (it registers only the `/bmi cleanup` command and touches nothing else).
local LEAK_MACROS = {
    "VuhDoDCShieldData",
    "VuhDoDCShieldNames",
    "Plumber Housing Macro",
}

local leakSet = {}
for _, name in ipairs(LEAK_MACROS) do leakSet[name] = true end

-- First character-macro index. WoW 12.1 moved MAX_ACCOUNT_MACROS onto Constants.MacroConsts;
-- fall back to the old global, then the stable literal (120), so counting works either way.
local function characterMacroBase()
    return ((Constants and Constants.MacroConsts and Constants.MacroConsts.MAX_ACCOUNT_MACROS)
        or MAX_ACCOUNT_MACROS or 120)
end

-- Count leaked macros without deleting, by walking both macro blocks (account then
-- character). GetMacroIndexByName only finds the first match, so a full walk is needed.
local function countLeaks()
    local counts, total = {}, 0
    local numAccount, numCharacter = GetNumMacros()
    local base = characterMacroBase()
    local function scan(from, to)
        for i = from, to do
            local name = GetMacroInfo(i)
            if name and leakSet[name] then
                counts[name] = (counts[name] or 0) + 1
                total = total + 1
            end
        end
    end
    scan(1, numAccount)
    scan(base + 1, base + numCharacter)
    return counts, total
end

-- Delete every macro carrying a leaked name. DeleteMacro shifts indices, so we re-query by
-- name after each removal; GetMacroIndexByName returns 0 (both lists searched) when none remain.
local function deleteLeaks()
    local counts, total = {}, 0
    for _, name in ipairs(LEAK_MACROS) do
        local idx = GetMacroIndexByName(name)
        while idx > 0 do
            DeleteMacro(idx)
            counts[name] = (counts[name] or 0) + 1
            total = total + 1
            idx = GetMacroIndexByName(name)
        end
    end
    return counts, total
end

ns:registerCommand("cleanup", nil, function(self, args)
    if InCombatLockdown() then
        ns:Print("can't delete macros in combat")
        return
    end

    local preview = args ~= nil and args:lower():find("^%s*p") ~= nil
    local counts, total
    if preview then
        counts, total = countLeaks()
    else
        counts, total = deleteLeaks()
    end

    if total == 0 then
        ns:Print(preview and "no leaked VuhDo/Plumber macros found" or "nothing to clean up")
        return
    end

    for _, name in ipairs(LEAK_MACROS) do
        if counts[name] then
            ns:Print(("%s %s: %d"):format(preview and "found" or "deleted", name, counts[name]))
        end
    end
    ns:Print(("%s %d macro%s"):format(preview and "would delete" or "deleted", total, total == 1 and "" or "s"))

    if not preview then
        ns:Print("re-drag the House button from the Housing dashboard to get a fresh teleport macro")
    end
end, "Delete leaked VuhDo/Plumber duplicate macros ('cleanup preview' to only count)")
