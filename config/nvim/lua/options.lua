local opt = vim.opt

opt.hidden = true

opt.tabstop = 4	        -- 2 space tabs
opt.softtabstop = 4     -- number of spaces in a tab when editing
opt.shiftwidth = 4      -- how much to shift by
opt.expandtab = true    -- tabs vs spaces, mwahahaha
opt.smartindent = true -- use c-like indents when no indentexpr is used

opt.showmatch = true -- show matching brackets
opt.scrolloff = 12 -- keep 12 lines below and above cursor always

opt.timeoutlen = 500


-- split reasonably
opt.splitbelow = true
opt.splitright = true

-- random stuff

opt.shortmess:append("c")
opt.diffopt:append("internal,algorithm:patience")

-- case in search
opt.ignorecase = true -- case insensitive
opt.smartcase = true -- all caps will be searched as all caps

opt.cmdheight = 1
opt.updatetime = 300 -- diagnostic message time
opt.signcolumn = "no"

vim.cmd("colorscheme xcode")

----consider turning this on some day
--opt.number = true -- show line numbers
--opt.relativenumber = true -- show relative numbers by default
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
vim.g.clipboard = {
  name = "Laptop Clipboard",
  copy = {
    ["*"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbcopy'"
    },
    ["+"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbcopy'"
    },
  },
  paste = {
    ["*"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbpaste'"
    },
    ["+"] = {
      "ssh",
      "-i",
      "~/.ssh/copy_paste_key_ed25519",
      "-p",
      "9001",
      "localhost",
      "'pbpaste'"
    },
  },
  cache_enabled = true,
}
