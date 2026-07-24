ignore = {"212", "21/_.*"}
max_line_length = 160
max_comment_line_length = 500

-- CI installs the Lua toolchain into the workspace (leafo/gh-actions-lua and
-- -luarocks); keep `luacheck .` off those trees.
exclude_files = {".lua", ".luarocks", ".install"}

-- Generated bundled-terms data: one long machine-generated line per spec/race section
-- (matches `/bmi export` output), so exempt it from the line-length limit.
files["data/spellterms.lua"] = { max_line_length = false }

-- busted specs (run from the repo root; see .busted). They loadfile() an addon file with the
-- (addonName, ns) vararg WoW passes it, against a hand-rolled namespace. The `std` below is a
-- closed list, so the spec tree additionally needs the stdlib bits it uses (io reads the toc to
-- check which modules reference a store key) plus the WoW globals it stubs onto _G: /bmi diff's
-- name resolvers, and the spellbook API + wipe that scan.lua drives.
files["spec/**/*.lua"] = {
  std = "+busted",
  read_globals = { "assert", "io", "loadfile", "loadstring", "require", "string" },
  globals = {
    "_G.GetSpecializationInfoByID", "_G.C_CreatureInfo",
    "_G.C_SpellBook", "_G.Enum", "_G.UnitClass", "_G.UnitRace", "_G.wipe",
  },
}

std = {
  -- Written globals (mutable): StaticPopupDialogs (we register BMI_ADD_TERM); MacroPopupFrame
  -- (`/bmi open` sets its .mode field before showing it).
  globals = { "_G", "StaticPopupDialogs", "MacroPopupFrame" },
  read_globals = {
    "ipairs",
    "next",
    "pairs",
    "select",
    "table",
    "tostring",
    "type",
    "wipe",

    "CreateFrame",
    "hooksecurefunc",

    -- Resolves bundled "Interface/Icons/<name>" → fileID for the name map
    "GetFileIDFromPath",

    -- SearchBoxTemplate support function
    "SearchBoxTemplate_OnTextChanged",

    -- Tooltip shown on icon hover
    "GameTooltip",

    -- Blizzard_MacroUI globals (loaded by the time our hooks fire; MacroPopupFrame is a
    -- *written* global — see `globals` above). MacroFrame + the popup mode enum are used by
    -- `/bmi open` to open the picker directly.
    "MacroFrame",
    "IconSelectorPopupFrameModes",

    -- The other hooked icon pickers: the transmog outfit-save popup (TransmogFrame.OutfitPopup,
    -- Blizzard_Transmog), the equipment set manager + bank tab menu (BankPanel.TabSettingsMenu,
    -- both Blizzard_UIPanels_Game), and the guild bank tab popup (Blizzard_GuildBankUI)
    "TransmogFrame",
    "GearManagerPopupFrame",
    "BankPanel",
    "GuildBankPopupFrame",

    -- Optional Bagnon integration: its bank module shows Bagnon.BankBag.Settings (a
    -- BankPanelTabSettingsMenuTemplate instance) in place of Blizzard's bank tab menu
    "Bagnon",

    -- `/bmi open` — load + show the macro UI on demand
    "InCombatLockdown",
    "C_AddOns",
    "ShowUIPanel",

    -- scan.lua — spellbook scan for automatic spell-name search terms
    "C_SpellBook",
    "Enum",
    "UnitRace",
    "UnitClass",

    -- scan.lua/dataset.lua — /bmi coverage + /bmi diff: enumerate class/specs, resolve names
    "GetNumClasses",
    "GetClassInfo",
    "C_SpecializationInfo",
    "GetSpecializationInfoForClassID",
    "GetSpecializationInfoByID",
    "C_CreatureInfo",

    -- aliases.lua — right-click context menu + add-term popup
    "MenuUtil",
    "StaticPopup_Show",
    "ACCEPT",
    "CANCEL",

    -- cleanup.lua — /bmi cleanup: delete leaked VuhDo/Plumber duplicate macros
    -- (InCombatLockdown is listed under the /bmi open globals above)
    "GetNumMacros",
    "GetMacroInfo",
    "GetMacroIndexByName",
    "DeleteMacro",
    "Constants",
    "MAX_ACCOUNT_MACROS",

    -- Suite dependencies (LibNUI optional — /bmi coverage uses its copy window when present)
    "LibNAddOn",
    "LibNUI",
  }
}
