ignore = {"212", "21/_.*"}
max_line_length = 160
max_comment_line_length = 500

std = {
  globals = { "_G" },
  read_globals = {
    "ipairs",
    "next",
    "tonumber",
    "type",
    "wipe",

    "CreateFrame",
    "hooksecurefunc",

    -- Macro icon C functions (same ones Blizzard's IconDataProvider uses)
    "GetLooseMacroIcons",
    "GetMacroIcons",
    "GetLooseMacroItemIcons",
    "GetMacroItemIcons",
    "GetFileIDFromPath",

    -- SearchBoxTemplate support function
    "SearchBoxTemplate_OnTextChanged",

    -- Blizzard_MacroUI globals (loaded by the time our hooks fire)
    "MacroPopupFrame",

    -- Suite dependency
    "LibNAddOn",
  }
}
