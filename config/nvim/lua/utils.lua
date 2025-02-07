local M = {}

function M.reload_module(name)
  package.loaded[name] = nil
  require(name)
end

function M.load_latest_session()
  require("persistence").load()
end

function M.create_scratch_buffer()
  local buf = vim.api.nvim_create_buf(true, true)
  vim.api.nvim_buf_set_name(buf, "[scratch]")
  vim.bo[buf.bufnr()].buftype = "nofile"
  vim.bo[buf.bufnr()].bufhidden = "hide"
  vim.bo[buf.bufnr()].noswapfile = "true"
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
