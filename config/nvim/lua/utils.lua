local M = {}

function M.reload_module(name)
  package.loaded[name] = nil
  require(name)
end

function M.load_latest_session()
  require("persistence").load()
end

return M
