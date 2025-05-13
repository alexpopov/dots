local opt = vim.opt
local M = {}

local set_tabs = function(count)
    opt.tabstop = count     -- 2 space tabs
    opt.softtabstop = count -- number of spaces in a tab when editing
    opt.shiftwidth = count  -- how much to shift by
end

M.set_tabs = set_tabs

opt.expandtab = true    -- tabs vs spaces, mwahahaha
opt.smartindent = true -- use c-like indents when no indentexpr is used
set_tabs(4)

opt.showmatch = true -- show matching brackets
opt.scrolloff = 12 -- keep 12 lines below and above cursor always

opt.timeoutlen = 500
opt.incsearch = true


-- split reasonably
opt.splitbelow = true
opt.splitright = true

opt.number = true
opt.relativenumber = true

-- random stuff

opt.shortmess:append("c")
opt.diffopt:append("internal,algorithm:patience")

-- case in search
opt.ignorecase = true -- case insensitive
opt.smartcase = true -- all caps will be searched as all caps

opt.cmdheight = 1
opt.updatetime = 300 -- diagnostic message time
opt.signcolumn = "no"

if vim.fn.getenv("COLORTERM") ~= vim.NIL then
  -- Millions and millions of colors
  vim.opt.termguicolors = true
end
vim.cmd("colorscheme lua_xcode")

return M
