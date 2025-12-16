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

return M
