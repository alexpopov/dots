local cmd = vim.cmd
local wk = require("which-key")

--  write/quit typos
cmd("command! WQ wq")
cmd("command! Wq wq")
cmd("command! W w")
cmd("command! Q q")

vim.g.mapleader = ","
vim.g.maplocalleader = "\\"

localLeader = '<localleader>'
leader = '<Leader>'
endl = '<CR>'

set_keymap = vim.api.nvim_set_keymap

-- Window Movement
set_keymap('n', '<C-J>', '<C-W><C-J>', { noremap = true, desc = "move to split south" })
set_keymap('n', '<C-H>', '<C-W><C-H>', { noremap = true, desc = "move to split west" })
set_keymap('n', '<C-K>', '<C-W><C-K>', { noremap = true, desc = "move to split north" })
set_keymap('n', '<C-L>', '<C-W><C-L>', { noremap = true, desc = "move to split east" })

-- leader commands
wk.add(
  {
    { "<Leader>f",  group = " Find" },
    { "<Leader>fH", ":Telescope help_tags<CR>", desc = "Help tags" },
    {
      "<Leader>fa",
      function()
        require 'telescope.builtin'.grep_string { shorten_path = true, word_match = '-w', only_sort_text
        = true, search = '' }
      end,
      desc = "Find All Files"
    },
    {
      "<Leader>fb",
      ":Telescope buffers<CR>",
      desc =
      "Find Buffer"
    },
    {
      "<Leader>ff",
      ":Telescope find_files<CR>",
      desc =
      "Find File"
    },
    {
      "<Leader>fh",
      ":Telescope current_buffer_fuzzy_find<CR>",
      desc =
      "Find Here (in this file)"
    },
    {
      "<Leader>fl",
      ":lua require'telescope.builtin'.grep_string{ shorten_path = true, grep_open_files = true, word_match = '-w', only_sort_text = true, search = ''}<CR>",
      desc =
      "Find Line (in open files)"
    },
    {
      "<Leader>fm",
      function()
        require 'telescope.builtin'.builtin(require("telescope.themes").get_dropdown({
          preview = false }))
      end,
      desc =
      "Search Telescopes"
    },
  })

-- leader commands that are recursive for normal and visual
wk.add(
  {
    { "<Leader>c",        group = " Comment", remap = true },
    { "<Leader>c<space>", ":Commentary<CR>",  desc = "Toggle", mode = { "v", "n" }, remap = true },
  }
)

-- local-leader commands
wk.add(
  {
    { "<localleader>b",   group = " buffers" },
    { "<localleader>bd",  ":call DeleteHiddenBuffers()",                                   desc = "Delete Hidden Buffers" },
    { "<localleader>e",   group = " edit" },
    { "<localleader>ed",  ":FZF ~/dots/<CR>",                                              desc = " edit dots config files" },
    { "<localleader>ev",  ":FZF ~/.config/nvim/<CR>",                                      desc = " vim files" },
    { "<localleader>g",   group = " go" },
    { "<localleader>gh",  ":lua require('tree-climber').goto_prev<CR>",                    desc = "previous" },
    { "<localleader>gj",  ":lua require('tree-climber').goto_child<CR>",                   desc = "child" },
    { "<localleader>gk",  ":lua require('tree-climber').goto_parent<CR>",                  desc = "parent" },
    { "<localleader>gl",  ":lua require('tree-climber').goto_next<CR>",                    desc = "next" },
    { "<localleader>q",   group = " config" },
    { "<localleader>qn",  ":lua vim.opt.number = true; vim.opt.relativenumber = true<CR>", desc = "line numbers" },
    { "<localleader>r",   group = " reload" },
    { "<localleader>rv",  group = " vim files" },
    { "<localleader>rvi", ":lua alp.utils.reload_module(lua_init)<CR>",                    desc = "init_lua.lua" },
    { "<localleader>rvl", ":lua alp.utils.reload_module(lsp)<CR>",                         desc = "lsp.lua" },
    { "<localleader>rvm", ":lua alp.utils.reload_module(mappings)<CR>",                    desc = "mappings.lua" },
    { "<localleader>rvo", ":lua alp.utils.reload_module(options)<CR>",                     desc = "options.lua" },
    { "<localleader>rvp", ":lua alp.utils.reload_module(plugins)<CR>",                     desc = "plugins.lua" },
    { "<localleader>rvv", ":source ~/.config/nvim/init.vim<CR>",                           desc = "init.vim" },
    { "<localleader>t",   group = " tabs" },
    { "<localleader>tn",  ":tabnew<CR>",                                                   desc = "New Tab" },
  }
)
