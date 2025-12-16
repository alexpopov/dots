local cmd = vim.cmd
local wk = require("which-key")

-- TODO: refactor this file into multiple files and have a top-level init.lua
-- file in the folder

-- Telescope picker for reloading config modules
local function reload_module_picker()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  -- Find lua files in config directory
  local config_path = vim.fn.stdpath("config") .. "/lua"
  local modules = {}

  local function scan_dir(path, prefix)
    local handle = vim.loop.fs_scandir(path)
    if not handle then return end

    while true do
      local name, type = vim.loop.fs_scandir_next(handle)
      if not name then break end

      if type == "file" and name:match("%.lua$") then
        local module_name = prefix .. name
        table.insert(modules, module_name)
      elseif type == "directory" and name ~= "private" then
        scan_dir(path .. "/" .. name, prefix .. name .. ".")
      end
    end
  end

  scan_dir(config_path, "")

  pickers.new({}, {
    prompt_title = "Reload Module",
    finder = finders.new_table({ results = modules }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local module_name = selection[1]:gsub("%.lua$", "")
          R(module_name)
          vim.notify("Reloaded: " .. selection[1], vim.log.levels.INFO)
        end
      end)
      return true
    end,
  }):find()
end

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

-- map <silent> <leader>fc /<<<<<<<\\|\|\|\|\|\|\|\|\\|=======\\|>>>>>>><CR>
-- leader commands
wk.add(
  {
    {
      "<Leader>fc", "/<<<<<<<\\||||||||\\|=======\\|>>>>>>><CR>",
      desc = "Find Conflicts"
    },
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
      "<Leader>fr",
      ":Telescope registers<CR>",
      desc =
      "Clipboard/Registers"
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
    { "<localleader>bd",  ":call DeleteHiddenBuffers()",                                   desc = "Delete Hidden Buffers" },
    { "<localleader>u",   function() require("utils").pick_function() end,                 desc = "Run function picker" },
    { "<localleader>g",   group = " go" },
    { "<localleader>gh",  ":lua require('tree-climber').goto_prev<CR>",                    desc = "previous" },
    { "<localleader>gj",  ":lua require('tree-climber').goto_child<CR>",                   desc = "child" },
    { "<localleader>gk",  ":lua require('tree-climber').goto_parent<CR>",                  desc = "parent" },
    { "<localleader>gl",  ":lua require('tree-climber').goto_next<CR>",                    desc = "next" },
    { "<localleader>q",   group = " config" },
    { "<localleader>qn",  ":lua vim.opt.number = true; vim.opt.relativenumber = true<CR>", desc = "line numbers" },
    { "<localleader>r",   group = " reload" },
    { "<localleader>rv",  reload_module_picker,                                           desc = "reload vim module (picker)" },
    { "<localleader>t",   group = " tabs" },
    { "<localleader>tn",  ":tabnew<CR>",                                                   desc = "New Tab" },
  }
)
