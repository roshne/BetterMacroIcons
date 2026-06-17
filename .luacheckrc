ignore = {"212", "21/_.*"}
max_line_length = 160
max_comment_line_length = 500

-- CI installs the Lua toolchain into the workspace (leafo/gh-actions-lua and
-- -luarocks); keep `luacheck .` off those trees.
exclude_files = {".lua", ".luarocks", ".install"}

std = {
  globals = { "_G" },
  read_globals = {
    "ipairs",
    "next",
    "pairs",
    "select",
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

    -- Suite dependency
    "LibNAddOn",
  }
}
