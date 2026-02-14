local wk = require("which-key")
local map = vim.keymap.set

-- Write/quit typo commands
vim.api.nvim_create_user_command("WQ", "wq", {})
vim.api.nvim_create_user_command("Wq", "wq", {})
vim.api.nvim_create_user_command("W", "w", {})
vim.api.nvim_create_user_command("Q", "q", {})

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"

-- Window Movement
-- TODO: do I still use C-K for window movement? It conflicts with LSP signature_help
map('n', '<C-J>', '<C-W><C-J>', { desc = "move to split south" })
map('n', '<C-H>', '<C-W><C-H>', { desc = "move to split west" })
map('n', '<C-K>', '<C-W><C-K>', { desc = "move to split north" })
map('n', '<C-L>', '<C-W><C-L>', { desc = "move to split east" })

-- Clear search highlighting
map('n', '<C-x>', ':nohl<CR>', { silent = true, desc = "clear search" })
map('n', '<Leader>r', ':nohl<CR>', { silent = true, desc = "clear search" })

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
