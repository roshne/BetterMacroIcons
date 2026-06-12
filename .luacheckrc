ignore = {"212", "21/_.*"}
max_line_length = 160
max_comment_line_length = 500

std = {
  globals = { "_G" },
  read_globals = {
    "ipairs",
    "math",
    "pairs",
    "select",
    "string",
    "table",
    "tonumber",
    "tostring",
    "type",
    "wipe",

    "CreateFrame",
    "hooksecurefunc",

    -- SearchBoxTemplate support function
    "SearchBoxTemplate_OnTextChanged",

    -- Blizzard_MacroUI globals (loaded by the time our hooks fire)
    "MacroPopupFrame",
    "MacroPopupFrameMixin",
    "IconSelectorPopupFrameTemplateMixin",

    -- Suite dependency
    "LibNAddOn",
  }
}
