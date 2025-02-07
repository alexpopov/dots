-- Port of old Xcode vimscript colorscheme I copied from
-- Christian Ohlin Jansson (john.christian.ohlin@gmail.com)
-- but then edited pretty heavily based on my own color preferences

vim.cmd("highlight clear")
vim.o.background = "light"

local c = {
  white = {cterm = 15, gui = "#ffffff"},
  black = {cterm = 16, gui = "#000000"},
  light_grey = {cterm = 255, gui = "#eeeeee"},
  middle_grey = {cterm = 253, gui = "#dadada"},
  dark_grey = {cterm = 236, gui = "#303030"},
  status_line_grey = {fg = 249, gui = "#b2b2b2"},
  unset = {cterm = "NONE", gui = "NONE"},
  skip = {cterm = nil, gui = nil},
  orange = {cterm = 226, gui="#ffff00"},
  text_black = {cterm = 234, gui = "#1c1c1c"},
  primary_blue = {cterm = 20, gui = "#0000df"},
  selection_blue = {cterm = 153, gui = "#afdfff"},

  -- Xcode Colors
  error_red = {cterm = 124, gui = "#af0000"},
  xcode_green = {cterm = 22, gui = "#005f00"},
  xcode_teal = {cterm = 30, gui = "#008787"},
  xcode_pink = {cterm = 163, gui = "#df00af"},
  xcode_red = {cterm = 160, gui = "#df0000"},
  xcode_brown = {cterm = 94, gui = "#875f00"},
  xcode_blue = {cterm = 20, gui = "#0000df"},
  xcode_purple = {cterm = 54, gui = "#5f0087"},
  xcode_grey = {cterm = 251, gui = "#c6c6c6"},

  bright_purple = {cterm = 91, gui = "#8700af"},
}

local group_colors = {
  -- Vim 7.0 colors
  CursorLine = {c.unset, c.unset, {}}, -- used to have cterm=NONE
  CursorColumn = {c.skip, c.dark_grey},
  MatchParen = {c.black, c.orange, {}}, -- used to have cterm=NONE
  Pmenu = {c.black, c.light_grey},
  PmenuSel = {c.black, c.middle_grey},

  -- General Section
  Cursor = {c.primary_blue, c.white},
  Normal = {c.black, c.white},
  NonText = {c.orange, c.white},
  LineNr = {{cterm = 239, gui = "#4e4e4e"}, c.unset}, -- attractive grey
  StatusLine = {c.status_line_grey, {cterm = 238, gui = "#444444"}},
  StatusLineNC = {{cterm = 241, gui = "#606060"}, c.status_line_grey}, -- Non-current window status line. It's a dimmer grey
  VertSplit = {c.white, c.white},
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
}

local links = {
  -- General Section
  Title = "Normal",
  SpecialKey = "Error",

  DiagnosticHint = "XcodeGrey",
  ["@keyword"] = "XcodePink",
  ["@variable.builtin"] = "XcodePink",
  ["@variable"] = "XcodeTeal",
  ["@namespace"] = "XcodePurple",
  ["@punctuation"] = "Normal",
  ["@operator"] = "Normal",
  ["@attribute.builtin"] = "XcodeBrown",
  ["@attribute"] = "XcodeBrown",
  Comment = "XcodeGreen",
  Constant = {link = "XcodePurple"},
  String = {link = "XcodeRed"},
  Identifier = {link = "XcodeTeal"},
  Function = {link = "Normal"},
  Type = {link = "XcodePurple"},
  Statement = {link = "XcodePink"},
  PreProc = {link = "XcodeBrown"},
  Number = "XcodeBlue",
  Special = "Keyword",
  Parens = {link = "Normal"},

  -- Diff Colors
  DiffAdded = "Comment",
  DiffChange = "pythonCustomFunc",
  diffRemoved = "String", -- TODO: typo in case?
  diffLine = "pythonStatement", -- TODO: typo in case?
  diffFile = "Identifier", -- TODO: typo in case?

  NvimInternalerror = "Error",

  -- Lua-specific
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
