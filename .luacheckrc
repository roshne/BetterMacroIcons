ignore = {"212", "21/_.*"}
max_line_length = 160
max_comment_line_length = 500

-- CI installs the Lua toolchain into the workspace (leafo/gh-actions-lua and
-- -luarocks); keep `luacheck .` off those trees.
exclude_files = {".lua", ".luarocks", ".install"}

std = {
  -- StaticPopupDialogs is written (we register our BMI_ADD_TERM dialog), so it's a mutable global
  globals = { "_G", "StaticPopupDialogs" },
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

    -- Blizzard_MacroUI globals (loaded by the time our hooks fire)
    "MacroPopupFrame",

    -- scan.lua — spellbook scan for automatic spell-name search terms
    "C_SpellBook",
    "Enum",
    "UnitRace",

    -- scan.lua — /bmi coverage: enumerate class/specs + resolve race names
    "GetNumClasses",
    "GetClassInfo",
    "C_SpecializationInfo",
    "GetSpecializationInfoForClassID",
    "C_CreatureInfo",

    -- aliases.lua — right-click context menu + add-term popup
    "MenuUtil",
    "StaticPopup_Show",
    "ACCEPT",
    "CANCEL",

    -- Suite dependency
    "LibNAddOn",
  }
}
