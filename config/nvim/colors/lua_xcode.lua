-- Port of old Xcode vimscript colorscheme I copied from
-- Christian Ohlin Jansson (john.christian.ohlin@gmail.com)
-- but then edited pretty heavily based on my own color preferences
-- Colors are most closely based on Xcode 5

vim.cmd("highlight clear")
vim.o.background = "light"

-- These are the 256-color choices I made by hand/eye based on Ohlin's original
local c = {
  white = {cterm = 15, gui = "#ffffff"},
  black = {cterm = 16, gui = "#000000"},
  light_grey = {cterm = 255, gui = "#eeeeee"},
  middle_grey = {cterm = 253, gui = "#dadada"},
  dark_grey = {cterm = 236, gui = "#303030"},
  status_line_grey = {cterm = 249, gui = "#b2b2b2"},
  unset = {cterm = "NONE", gui = "NONE"},
  skip = {cterm = nil, gui = nil},
  highlight_yellow = {cterm = 226, gui="#ffff00"},
  text_black = {cterm = 234, gui = "#1c1c1c"},
  primary_blue = {cterm = 20, gui = "#0000df"},
  selection_blue = {cterm = 153, gui = "#afdfff"},
  selection_pink = {cterm = 219, gui = "#FFB0FF"},

  -- Xcode Colors
  error_red = {cterm = 124, gui = "#af0000"},
  xcode_green = {cterm = 22, gui = "#005f00"},
  xcode_teal = {cterm = 30, gui = "#008787"},
  xcode_pink = {cterm = 163, gui = "#b30061"},
  xcode_red = {cterm = 160, gui = "#df0000"},
  xcode_brown = {cterm = 94, gui = "#875f00"},
  xcode_blue = {cterm = 20, gui = "#0000df"},
  xcode_purple = {cterm = 54, gui = "#5f0087"},
  xcode_grey = {cterm = 251, gui = "#c6c6c6"},

  bright_purple = {cterm = 91, gui = "#4d009e"},
}

local xcode5_basic_c = vim.deepcopy(c)
xcode5_basic_c.xcode_green.gui = "#008000" -- or maybe 1c8517
xcode5_basic_c.xcode_teal.gui = "#2b839f"
xcode5_basic_c.xcode_red.gui = "#a31414"

local xcode5_presentation_c = vim.deepcopy(c)
xcode5_presentation_c.xcode_green.gui = "#1c8517"
xcode5_presentation_c.xcode_teal.gui = "#458a94"
xcode5_presentation_c.xcode_brown.gui = "#80662b"
xcode5_presentation_c.xcode_blue.gui = "#000dfc"
xcode5_presentation_c.bright_purple.gui = "#4d009e"
xcode5_presentation_c.xcode_purple.gui = "#2e0d6e"
xcode5_presentation_c.xcode_pink.gui = "#b30061"
xcode5_presentation_c.xcode_red.gui = "#b8000f"

c = xcode5_presentation_c

local group_colors = {
  -- Vim 7.0 colors
  CursorLine = {c.unset, c.unset, {}}, -- used to have cterm=NONE
  CursorColumn = {c.skip, c.dark_grey},
  MatchParen = {c.black, c.highlight_yellow, {}}, -- used to have cterm=NONE
  Pmenu = {c.black, c.light_grey},
  PmenuSel = {c.black, c.middle_grey},

  -- Tab line (top of screen)
  TabLine = {{cterm = 241, gui = "#606060"}, c.light_grey}, -- inactive tabs: grey text on light grey
  TabLineSel = {c.black, c.white, {bold = true}}, -- active tab: black on white, bold
  TabLineFill = {c.skip, c.light_grey}, -- empty tabline area: light grey

  -- General Section
  Cursor = {c.primary_blue, c.white},
  Normal = {c.black, c.white},
  NonText = {c.highlight_yellow, c.white},
  LineNr = {{cterm = 239, gui = "#4e4e4e"}, c.unset}, -- attractive grey
  CursorLineNr = {c.black, c.unset, {bold = true}}, -- current line number stands out
  StatusLine = {c.status_line_grey, {cterm = 238, gui = "#444444"}},
  StatusLineNC = {{cterm = 241, gui = "#606060"}, c.status_line_grey}, -- Non-current window status line. It's a dimmer grey
  VertSplit = {c.white, c.white},
  WinSeparator = {{cterm = 253, gui = "#dadada"}, c.white}, -- modern nvim replacement for VertSplit
  Folded = {c.middle_grey, c.text_black},
  FoldColumn = {c.unset, c.unset},
  Visual = {c.skip, c.selection_blue},
  Error = {c.white, c.error_red},

  -- Custom Xcode Highlight Groups to Link Against
  XcodeGreen = {c.xcode_green, c.skip},
  XcodeTeal = {c.xcode_teal, c.skip},
  XcodePink = {c.xcode_pink, c.skip},
  XcodeRed = {c.xcode_red, c.skip},
  XcodeBrown = {c.xcode_brown, c.skip},
  XcodeBlue = {c.xcode_blue, c.skip},
  XcodePurple = {c.xcode_purple, c.skip},
  XcodeGrey = {c.xcode_grey, c.skip},

  -- More Groups
  Todo = {c.xcode_red, c.skip},
  Keyword = {c.bright_purple, c.skip},
  Search = {c.dark_grey, c.selection_blue, {underline = true}},
  Delimiter = {c.bright_purple, c.skip, {bold = true}},

  -- Floating windows (telescope, hover docs, etc.)
  NormalFloat = {c.black, c.light_grey},
  FloatBorder = {{cterm = 241, gui = "#606060"}, c.light_grey},
  FloatTitle = {c.xcode_pink, c.light_grey, {bold = true}},

  -- Diff highlights (background colors for visibility on light theme)
  -- TODO: review these pastel colors and decide if they match the xcode vibe
  DiffAdd = {c.skip, {cterm = 194, gui = "#d7ffd7"}},
  DiffDelete = {c.skip, {cterm = 224, gui = "#ffd7d7"}},
  DiffChange = {c.skip, {cterm = 189, gui = "#d7d7ff"}},
  DiffText = {c.skip, {cterm = 229, gui = "#ffffaf"}, {bold = true}},

  -- render-markdown.nvim
  RenderMarkdownH1 = {c.black, c.skip, {bold = true}},
  RenderMarkdownH2 = {c.black, c.skip, {bold = true}},
  RenderMarkdownH3 = {c.black, c.skip, {bold = true}},
  RenderMarkdownH4 = {c.black, c.skip, {bold = true}},
  RenderMarkdownH5 = {c.black, c.skip, {bold = true}},
  RenderMarkdownH6 = {c.black, c.skip, {bold = true}},
  RenderMarkdownH1Bg = {c.skip, {cterm = 225, gui = "#f4f1f9"}, {bold = true}},   -- Soft Lavender
  RenderMarkdownH2Bg = {c.skip, {cterm = 189, gui = "#eef0ff"}, {bold = true}},   -- Pale Ice Blue
  RenderMarkdownH3Bg = {c.skip, {cterm = 224, gui = "#fdf2f7"}, {bold = true}},   -- Shell Pink
  RenderMarkdownH4Bg = {c.skip, {cterm = 194, gui = "#f1f8f1"}, {bold = true}},   -- Mint Tint
  RenderMarkdownH5Bg = {c.skip, {cterm = 195, gui = "#f0f7f8"}, {bold = true}},   -- Misty Cyan
  RenderMarkdownH6Bg = {c.skip, {cterm = 230, gui = "#faf8f2"}, {bold = true}},   -- Warm Parchment
  RenderMarkdownCode = {c.skip, {cterm = 231, gui = "#f8f8f8"}},
  RenderMarkdownCodeInline = {c.skip, {cterm = 231, gui = "#f8f8f8"}},

  -- For My Stuff
  AiRecommendation = {c.skip, c.selection_pink},
}

local links = {
  -- General Section
  Title = "Normal",
  SpecialKey = "Error",

  DiagnosticError = "XcodeRed",
  DiagnosticWarn = "XcodeBrown",
  DiagnosticInfo = "XcodeBlue",
  DiagnosticHint = "XcodeGrey",
  -- Treesitter highlights
  ["@keyword"] = "XcodePink",
  ["@keyword.return"] = "XcodePink",
  ["@keyword.function"] = "XcodePink",
  ["@keyword.operator"] = "XcodePink",
  ["@keyword.conditional"] = "XcodePink",
  ["@keyword.repeat"] = "XcodePink",
  ["@keyword.exception"] = "XcodePink",
  ["@keyword.import"] = "XcodeBrown",
  ["@conditional"] = "XcodePink",   -- legacy fallback
  ["@repeat"] = "XcodePink",        -- legacy fallback
  ["@exception"] = "XcodePink",     -- legacy fallback
  ["@include"] = "XcodeBrown",      -- legacy fallback
  ["@variable"] = "XcodeTeal",
  ["@variable.builtin"] = "XcodePink",
  ["@variable.parameter"] = "XcodeTeal",
  ["@variable.member"] = "XcodeTeal",
  ["@property"] = "XcodeTeal",
  ["@field"] = "XcodeTeal",         -- legacy fallback
  ["@namespace"] = "XcodePurple",
  ["@module"] = "XcodePurple",
  ["@type"] = "XcodePurple",
  ["@type.builtin"] = "XcodePurple",
  ["@constant"] = "XcodePurple",
  ["@constant.builtin"] = "XcodePurple",
  ["@boolean"] = "XcodePurple",
  ["@number"] = "XcodeBlue",
  ["@number.float"] = "XcodeBlue",
  ["@string"] = "XcodeRed",
  ["@string.escape"] = "XcodeBrown",
  ["@string.special"] = "XcodeBrown",
  ["@character"] = "XcodeBlue",
  ["@comment"] = "XcodeGreen",
  ["@function"] = "Normal",
  ["@function.call"] = "Normal",
  ["@function.builtin"] = "XcodePurple",
  ["@function.method"] = "Normal",
  ["@function.method.call"] = "Normal",
  ["@constructor"] = "XcodePurple",
  ["@punctuation"] = "Normal",
  ["@punctuation.bracket"] = "Normal",
  ["@punctuation.delimiter"] = "Normal",
  ["@operator"] = "Normal",
  ["@attribute.builtin"] = "XcodeBrown",
  ["@attribute"] = "XcodeBrown",
  ["@tag"] = "XcodePink",
  ["@tag.attribute"] = "XcodeTeal",
  ["@tag.delimiter"] = "Normal",
  Comment = "XcodeGreen",
  Constant = "XcodePurple",
  String = "XcodeRed",
  Identifier = "XcodeTeal",
  Function = "Normal",
  Type = "XcodePurple",
  Statement = "XcodePink",
  PreProc = "XcodeBrown",
  Number = "XcodeBlue",
  Special = "Keyword",
  Parens = "Normal",

  -- Diff Colors (DiffAdd/Change/Delete/Text defined in group_colors with backgrounds)
  diffAdded = "DiffAdd",
  diffChanged = "DiffChange",
  diffRemoved = "DiffDelete",
  diffLine = "XcodePurple",
  diffFile = "Identifier",

  NvimInternalerror = "Error",

  EndOfBuffer = "LineNr",

  -- Telescope
  TelescopePromptCounter = "LineNr",

  -- Lua-specific (table constructors {} should be normal, not purple)
  ["@constructor.lua"] = "Normal",

  -- Javascript (lol wtf why, and more messed up case)
  javaScriptReserved = "XcodePurple",
  javaScriptNumber = "Number",
  javaScriptFuncArg = "XcodePurple",
  javascriptBlock = "XcodeTeal",
  javascriptIdentifier = "XcodePurple",

  -- HTML: more wtf
  htmlArg = "XcodeTeal",
  htmlString = "Number", -- why is it blue?
  htmlComment = "Comment",
  htmlCommentParent = "htmlComment",
  htmlTag = "Normal",
  htmlTagN = "htmlTag",
  htmlEndTag = "htmlTag",
}

local function safely_set_hl(caller, group, style)
    local function set_hl()
      vim.api.nvim_set_hl(0, group, style)
    end
    local status, err = pcall(set_hl)
    if not status then
      vim.notify("Error setting highlight " .. caller .. " for group '" .. group
      .. "' with style: " .. vim.inspect(style) .. "\n" .. err)
    end
end

local function set_highlight_link(group, link)
  if type(link) == "table" then
    safely_set_hl("link", group, link)
  else -- assume string name
    safely_set_hl("link", group, {link = link})
  end
end


local function set_highlight_colors(group, colors)
  local fg = colors[1]
  local bg = colors[2]
  local cterm = colors[3] -- usually unset

  if fg and bg then
    local style = { ctermfg = fg.cterm, fg = fg.gui, ctermbg = bg.cterm, bg = bg.gui }
    -- set cterm if defined
    if cterm then style.cterm = cterm end
    safely_set_hl("color", group, style)
  else
    local error_string ="Error with group '" .. group .. "': "
    if fg == nil then
      error_string = error_string .. "foreground nil "
    elseif bg == nil then
      error_string = error_string .. "background nil "
    else
      error_string = error_string .. "both foreground and background are missing"
    end
    vim.notify(error_string, "warning")
  end
end


for name, colors in pairs(group_colors) do
  set_highlight_colors(name, colors)
end

for name, link in pairs(links) do
  set_highlight_link(name, link)
end

-- This is from the XML file dictating Xcode 5.1.1 Presentation Mode
--
-- xcode.syntax.attribute
-- 0.512 0.423 0.157 1          -- xcode brown? #80662b
--
-- xcode.syntax.preprocessor
-- 0.429738 0.124544 0.052806 1 -- darker xcode brown #6e1f0f
--
-- xcode.syntax.identifier.macro
-- 0.391 0.22 0.125 1            -- xcode brown #63361f
--
--
--
-- xcode.syntax.character
-- 0 0.0445914 0.99822 1        -- xcode blue #000dfc
--
-- xcode.syntax.number
-- 0 0.0445914 0.99822 1        -- xcode blue for sure, same as above
--
--
--
-- xcode.syntax.comment
-- 0.114885 0.521968 0.0985181 1 -- xcode green #1c8517
--
--
--
-- xcode.syntax.identifier.class
-- 0.187687 0.436989 0.472891 1  -- xcode teal #307078
--
-- xcode.syntax.identifier.class.system
-- 0.265175 0.536459 0.576187 1  -- lighter teal? #458a94
--
-- xcode.syntax.identifier.variable
-- 0.265175 0.536459 0.576187 1  -- same teal as lighter teal, basically #458a91
--
--
--
-- xcode.syntax.identifier.type.system
-- 0.302778 0 0.619657 1         -- xcode purple #4d009e
--
-- xcode.syntax.identifier.constant.system
-- 0.181 0.052 0.431 1           -- darker purple? #2e0d6e
--
-- xcode.syntax.identifier.function.system
-- 0.181 0.052 0.431 1           -- same darker
--
-- xcode.syntax.identifier.type
-- 0.359 0.149 0.601 1           -- even more purple #5c2699
--
-- xcode.syntax.identifier.variable.system
-- 0.359 0.149 0.601 1           -- same as purple above
--
--
--
-- xcode.syntax.identifier.constant
-- 0.149 0.278 0.294 1           -- dark grey? #26474a
--
-- xcode.syntax.identifier.function
-- 0.123594 0.233835 0.24757 1   -- another dark grey? #1f3b42
--
--
-- xcode.syntax.keyword
-- 0.706817 0 0.382636 1         -- rich hot pink #b30061
--
--
--
-- xcode.syntax.identifier.plain
-- 0 0 0 1                       -- pure black
--
-- xcode.syntax.plain
-- 0 0 0 1                       -- black
--
--
--
-- xcode.syntax.string
-- 0.727675 0 0.0666152 1        -- xcode string red #b8000f
--
--
-- xcode.syntax.url
-- 0.055 0.055 1 1               -- don't care about URLs

