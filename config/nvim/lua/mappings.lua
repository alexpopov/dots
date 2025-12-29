local cmd = vim.cmd
local wk = require("which-key")

-- TODO: refactor this file into multiple files and have a top-level init.lua
-- file in the folder

--  write/quit typos
cmd("command! WQ wq")
cmd("command! Wq wq")
cmd("command! W w")
cmd("command! Q q")

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"

local set_keymap = vim.api.nvim_set_keymap

-- Window Movement
set_keymap('n', '<C-J>', '<C-W><C-J>', { noremap = true, desc = "move to split south" })
set_keymap('n', '<C-H>', '<C-W><C-H>', { noremap = true, desc = "move to split west" })
set_keymap('n', '<C-K>', '<C-W><C-K>', { noremap = true, desc = "move to split north" })
set_keymap('n', '<C-L>', '<C-W><C-L>', { noremap = true, desc = "move to split east" })

-- Clear search highlighting
set_keymap('n', '<C-x>', ':nohl<CR>', { noremap = true, silent = true, desc = "clear search" })
set_keymap('n', '<Leader>r', ':nohl<CR>', { noremap = true, silent = true, desc = "clear search" })

-- map <silent> <leader>fc /<<<<<<<\\|\|\|\|\|\|\|\|\\|=======\\|>>>>>>><CR>
-- leader commands
wk.add(
  {
    {
      "<Leader>fc", "/<<<<<<<\\||||||||\\|=======\\|>>>>>>><CR>",
      desc = "Find Conflicts"
    },
    { "<Leader>f",  group = " Find" },
  })

-- leader commands that are recursive for normal and visual
wk.add(
  {
    { "<Leader>c",        group = " Comment", remap = true },
    { "<Leader>c<space>", ":Commentary<CR>",  desc = "Toggle", mode = { "v", "n" }, remap = true },
  }
)

-- edit files fast
wk.add(
{
  { "<localleader>e", group = " edit" },
  { "<localleader>ed", ":FZF ~/dots/<CR>", desc = " dots config files" },
  { "<localleader>ev", ":FZF ~/.config/nvim/<CR>", desc = " vim files" },
  { "<localleader>es", ":FZF ~/fbsource/fbcode/scripts/alexpopov/<CR>", desc = " fbcode scripts" },
}
)

-- local-leader commands
wk.add(
  {
    { "<localleader>b",   group = " buffers" },
    { "<localleader>bd",  function() require("utils").delete_hidden_buffers() end,            desc = "Delete Hidden Buffers" },
    { "<localleader>u",   function() require("telescope.pick_function")() end,               desc = "Run function picker" },
    { "<localleader>q",   group = " config" },
    { "<localleader>qn",  ":lua vim.opt.number = true; vim.opt.relativenumber = true<CR>", desc = "line numbers" },
    { "<localleader>r",   group = " reload" },
    { "<localleader>rv",  function() require("telescope.reload_module")() end,              desc = "reload vim module (picker)" },
    { "<localleader>t",   group = " tabs" },
    { "<localleader>tn",  ":tabnew<CR>",                                                   desc = "New Tab" },
  }
)
