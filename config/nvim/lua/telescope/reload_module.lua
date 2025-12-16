local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

return function()
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
