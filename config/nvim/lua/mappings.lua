local cmd = vim.cmd
local wk = require("which-key")

--  write/quit typos
cmd("command! WQ wq")
cmd("command! Wq wq")
cmd("command! W w")
cmd("command! Q q")

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"

local set_keymap = vim.api.nvim_set_keymap

-- Window Movement
-- TODO: do I still use C-K for window movement? It conflicts with LSP signature_help
set_keymap('n', '<C-J>', '<C-W><C-J>', { noremap = true, desc = "move to split south" })
set_keymap('n', '<C-H>', '<C-W><C-H>', { noremap = true, desc = "move to split west" })
set_keymap('n', '<C-K>', '<C-W><C-K>', { noremap = true, desc = "move to split north" })
set_keymap('n', '<C-L>', '<C-W><C-L>', { noremap = true, desc = "move to split east" })

-- Clear search highlighting
set_keymap('n', '<C-x>', ':nohl<CR>', { noremap = true, silent = true, desc = "clear search" })
set_keymap('n', '<Leader>r', ':nohl<CR>', { noremap = true, silent = true, desc = "clear search" })

-- All which-key registrations
wk.add({
  -- Leader: find
  { "<Leader>f",  group = "find" },
  { "<Leader>fc", "/<<<<<<<\\||||||||\\|=======\\|>>>>>>><CR>", desc = "find conflicts" },

  -- Leader: comment (recursive for normal and visual)
  { "<Leader>c",        group = "comment", remap = true },
  { "<Leader>c<space>", ":Commentary<CR>",  desc = "toggle", mode = { "v", "n" }, remap = true },

  -- Leader: LSP (group only, keymaps set in lsp.lua on LspAttach)
  { "<Leader>a",  group = "LSP" },
  { "<Leader>aw", group = "workspace" },
  { "<Leader>ac", group = "code" },

  -- Leader: trouble
  { "<Leader>t",  group = "trouble" },

  -- Localleader: edit files fast
  { "<localleader>e",  group = "edit" },
  { "<localleader>ed", ":FZF ~/dots/<CR>",                                desc = "dots config files" },
  { "<localleader>ev", ":FZF ~/.config/nvim/<CR>",                        desc = "vim files" },
  { "<localleader>es", ":FZF ~/fbsource/fbcode/scripts/alexpopov/<CR>",   desc = "fbcode scripts" },

  -- Localleader: buffers
  { "<localleader>b",  group = "buffers" },
  { "<localleader>bd", function() require("utils").delete_hidden_buffers() end, desc = "delete hidden buffers" },

  -- Localleader: utilities
  { "<localleader>u", function() require("telescope.pick_function")() end, desc = "function picker" },

  -- Localleader: config
  { "<localleader>q",  group = "config" },
  { "<localleader>qn", ":lua vim.opt.number = true; vim.opt.relativenumber = true<CR>", desc = "line numbers" },

  -- Localleader: reload
  { "<localleader>r",  group = "reload" },
  { "<localleader>rv", function() require("telescope.reload_module")() end, desc = "reload vim module" },

  -- Localleader: tabs
  { "<localleader>t",  group = "tabs" },
  { "<localleader>tn", ":tabnew<CR>", desc = "new tab" },
})
