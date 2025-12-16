local pickers = require("telescope.pickers")
local finders = require("telescope.finders")
local conf = require("telescope.config").values
local actions = require("telescope.actions")
local action_state = require("telescope.actions.state")

return function()
  local entries = {}

  local function get_nparams(fn)
    local info = debug.getinfo(fn, "u")
    return info and info.nparams or 0
  end

  -- Scan telescope/ folder for modules
  local telescope_path = vim.fn.stdpath("config") .. "/lua/telescope"
  local handle = vim.loop.fs_scandir(telescope_path)
  if handle then
    while true do
      local name, ftype = vim.loop.fs_scandir_next(handle)
      if not name then break end

      if ftype == "file" and name:match("%.lua$") then
        local mod_name = "telescope." .. name:gsub("%.lua$", "")
        local ok, mod = pcall(require, mod_name)
        if ok and type(mod) == "function" then
          table.insert(entries, { display = mod_name, mod = mod_name, nparams = get_nparams(mod) })
        end
      end
    end
  end

  -- Also include utils module functions
  local ok, utils = pcall(require, "utils")
  if ok and type(utils) == "table" then
    for fn_name, fn in pairs(utils) do
      if type(fn) == "function" then
        table.insert(entries, { display = "utils." .. fn_name, mod = "utils", fn = fn_name, nparams = get_nparams(fn) })
      end
    end
  end

  -- Sort entries alphabetically
  table.sort(entries, function(a, b) return a.display < b.display end)

  pickers.new({}, {
    prompt_title = "Run Function",
    finder = finders.new_table({
      results = entries,
      entry_maker = function(entry)
        return { value = entry, display = entry.display, ordinal = entry.display }
      end,
    }),
    sorter = conf.generic_sorter({}),
    attach_mappings = function(prompt_bufnr, map)
      actions.select_default:replace(function()
        actions.close(prompt_bufnr)
        local selection = action_state.get_selected_entry()
        if selection then
          local entry = selection.value
          if entry.nparams == 0 then
            -- No args needed, call directly
            if entry.fn then
              require(entry.mod)[entry.fn]()
            else
              require(entry.mod)()
            end
          else
            -- Has args, put in command prompt
            local cmd
            if entry.fn then
              cmd = ":lua require('" .. entry.mod .. "')." .. entry.fn .. "("
            else
              cmd = ":lua require('" .. entry.mod .. "')("
            end
            vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd, true, false, true), "n", false)
          end
        end
      end)
      return true
    end,
  }):find()
end
