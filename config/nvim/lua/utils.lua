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

return M
