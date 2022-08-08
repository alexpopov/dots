local M = {}

function M.reload_module(name)
  package.loaded[name] = nil
  require(name)
end

return M
