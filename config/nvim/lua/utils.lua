local M = {}

function M.load_latest_session()
  require("persistence").load()
end

function M.save_session()
  require("persistence").save()
end

function M.create_scratch_buffer()
  local dir = "/tmp/nvim." .. os.getenv("USER")
  vim.fn.mkdir(dir, "p")
  local filename = dir .. "/scratch_" .. os.date("%Y%m%d_%H%M%S") .. ".txt"
  vim.cmd.edit(filename)
end

function M.safe_require(module_name)
  local status_ok, module = pcall(require, module_name)
  if not status_ok then
    vim.notify("Couldn't load module '" .. module_name .. "'", vim.log.levels.INFO)
    return nil
  end
  return module
end

function M.pick_function()
  local pickers = require("telescope.pickers")
  local finders = require("telescope.finders")
  local conf = require("telescope.config").values
  local actions = require("telescope.actions")
  local action_state = require("telescope.actions.state")

  local modules = { "utils" } -- add more module names here, e.g. "alp"
  local entries = {}

  for _, mod_name in ipairs(modules) do
    local ok, mod = pcall(require, mod_name)
    if ok and type(mod) == "table" then
      for fn_name, fn in pairs(mod) do
        if type(fn) == "function" and fn_name ~= "pick_function" then
          table.insert(entries, { display = mod_name .. "." .. fn_name, mod = mod_name, fn = fn_name })
        end
      end
    end
  end

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
          local cmd = ":lua require('" .. selection.value.mod .. "')." .. selection.value.fn .. "("
          vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(cmd, true, false, true), "n", false)
        end
      end)
      return true
    end,
  }):find()
end

return M
