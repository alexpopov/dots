alp = {} -- global variable for my stuff
-- should not be used in modules to avoid cycles or dependency ordering constraints

alp.utils = require("utils")

require("plugins")
require("options")
require("mappings")
require("lsp")

if os.getenv("ENABLE_PRIVATE_FACEBOOK")
then
  require("private/meta")
end
