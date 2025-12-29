-- Source private fb stuff if available
local admin_scripts = vim.fn.getenv("ADMIN_SCRIPTS")
if admin_scripts ~= vim.NIL then
  local master_vimrc = admin_scripts .. "/master.vimrc"
  if vim.fn.filereadable(master_vimrc) == 1 then
    vim.cmd("source " .. master_vimrc)
  end
end

-- Load main Lua config
require("lua_init")

-- Provider settings
vim.g.python3_host_prog = vim.fn.getenv("NVIM_PYTHON")
vim.g.loaded_node_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_ruby_provider = 0

-- Filetype detection for special files
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.histedit.hg.txt",
  callback = function() vim.bo.filetype = "conf" end,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.gitconfig",
  callback = function() vim.bo.filetype = "gitconfig" end,
})

vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "*.json",
  callback = function() vim.bo.filetype = "jsonc" end,
})

-- skhd config file highlighting
vim.api.nvim_create_autocmd({ "BufRead", "BufNewFile" }, {
  pattern = "skhdrc",
  callback = function()
    vim.cmd([[syntax match alert_text 'alert\.sh \w\+ \(\w\+\)?']])
    vim.cmd([[syntax match yabai_text 'yabai_utils\.sh \w\+ \(\w\+\)?']])
    vim.cmd([[hi link alert_text XcodePink]])
    vim.cmd([[hi link yabai_text XcodeTeal]])
  end,
})

-- Clang-format mapping
vim.keymap.set('n', '<Leader>afc', ':%py3f /usr/local/share/clang/clang-format.py<CR>',
  { silent = true, desc = "clang-format file" })
