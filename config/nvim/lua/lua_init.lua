alp = {} -- global variable for my stuff
-- should not be used in modules to avoid cycles or dependency ordering constraints

alp.utils = require("utils")

require("config.lazy")
require("options")
require("mappings")
require("lsp")
require("globals")

if os.getenv("ENABLE_PRIVATE_FACEBOOK")
then
  -- Private Meta-only module. Absent on non-Meta machines / CI / anywhere it
  -- isn't on the Lua runtime path, so load it optionally: its absence must not
  -- crash init (E5113). Warn instead of aborting.
  local ok, err = pcall(require, "private/meta")
  if not ok then
    vim.schedule(function()
      vim.notify("private/meta not loaded: " .. tostring(err), vim.log.levels.WARN)
    end)
  end
end
