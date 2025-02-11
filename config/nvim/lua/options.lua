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

--
---- show absolute numbers in insert mode, relative in normal mode
--vim.cmd([[
--  augroup numbertoggle
--    autocmd!
--    autocmd BufEnter,FocusGained,InsertLeave * set relativenumber
--    autocmd BufLeave,FocusLost,InsertEnter   * set norelativenumber
--  augroup END
--]])

-- configure pasting back to Laptop... should probably gate this behind some
-- check eventually

-- vim.g.clipboard = {
--   name = "Laptop Clipboard",
--   copy = {
--     ["*"] = {
--       "ssh",
--       "-i",
--       "~/.ssh/copy_paste_key_ed25519",
--       "-p",
--       "9001",
--       "localhost",
--       "'pbcopy'"
--     },
--     ["+"] = {
--       "ssh",
--       "-i",
--       "~/.ssh/copy_paste_key_ed25519",
--       "-p",
--       "9001",
--       "localhost",
--       "'pbcopy'"
--     },
--   },
--   paste = {
--     ["*"] = {
--       "ssh",
--       "-i",
--       "~/.ssh/copy_paste_key_ed25519",
--       "-p",
--       "9001",
--       "localhost",
--       "'pbpaste'"
--     },
--     ["+"] = {
--       "ssh",
--       "-i",
--       "~/.ssh/copy_paste_key_ed25519",
--       "-p",
--       "9001",
--       "localhost",
--       "'pbpaste'"
--     },
--   },
--   cache_enabled = true,
-- }

return M
