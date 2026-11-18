local map = vim.keymap.set

-- Write/quit typo commands
vim.api.nvim_create_user_command("WQ", "wq", {})
vim.api.nvim_create_user_command("Wq", "wq", {})
vim.api.nvim_create_user_command("W", "w", {})
vim.api.nvim_create_user_command("Q", "q", {})

-- Buffer close without closing split (replaces vim-bufkill)
vim.api.nvim_create_user_command("BD", function(o) require("utils").close_buffer(o.bang) end, { bang = true })
vim.api.nvim_create_user_command("BW", function(o) require("utils").close_buffer(o.bang) end, { bang = true })

-- On-demand LSP
vim.api.nvim_create_user_command("LspEnable", function() require("utils").enable_lsp() end, {})

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"

-- Window Movement
map('n', '<C-J>', '<C-W><C-J>', { desc = "move to split south" })
map('n', '<C-H>', '<C-W><C-H>', { desc = "move to split west" })
map('n', '<C-K>', '<C-W><C-K>', { desc = "move to split north" })
map('n', '<C-L>', '<C-W><C-L>', { desc = "move to split east" })

-- Clear search highlighting
map('n', '<C-x>', ':nohl<CR>', { silent = true, desc = "clear search" })
map('n', '<Leader>r', ':nohl<CR>', { silent = true, desc = "clear search" })

-- Leader: find
map('n', '<Leader>fc', '/<<<<<<<\\||||||||\\|=======\\|>>>>>>><CR>', { desc = "find conflicts" })

-- Leader: comment (uses Neovim 0.10+ built-in gc / gcc)
map('n', '<Leader>c<space>', 'gcc', { remap = true, desc = "toggle comment" })
map('v', '<Leader>c<space>', 'gc', { remap = true, desc = "toggle comment" })

-- Localleader: edit files fast (via Telescope instead of fzf.vim)
map('n', '<localleader>ed', function()
  require("telescope.builtin").find_files({ cwd = vim.fn.expand("~/dots") })
end, { desc = "dots config files" })
map('n', '<localleader>ev', function()
  require("telescope.builtin").find_files({ cwd = vim.fn.expand("~/.config/nvim") })
end, { desc = "vim files" })
map('n', '<localleader>es', function()
  require("telescope.builtin").find_files({ cwd = vim.fn.expand("~/fbsource/users/al/alexpopov") })
end, { desc = "personal scripts" })

-- Localleader: buffers
map('n', '<localleader>bd', function() require("utils").delete_hidden_buffers() end, { desc = "delete hidden buffers" })
map('n', '<localleader>bk', function() require("utils").close_buffer() end, { desc = "close buffer (keep split)" })

-- Localleader: utilities (includes utils.enable_lsp, utils.mason, etc.)
map('n', '<localleader>u', function() require("telescope.pick_function")() end, { desc = "function picker" })

-- Localleader: config
map('n', '<localleader>qn', ':lua vim.opt.number = true; vim.opt.relativenumber = true<CR>', { desc = "line numbers" })

-- Localleader: reload
map('n', '<localleader>rv', function() require("telescope.reload_module")() end, { desc = "reload vim module" })

-- Localleader: tabs
map('n', '<localleader>tn', ':tabnew<CR>', { desc = "new tab" })

-- Localleader: yank to system clipboard (+ register, synced via OSC52)
map({ 'n', 'v' }, '<localleader>y', '"+y', { desc = "yank to system clipboard" })
map('n', '<localleader>Y', '"+yy', { desc = "yank whole line to system clipboard" })
