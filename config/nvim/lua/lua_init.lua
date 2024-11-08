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
  require("private/meta")
end
