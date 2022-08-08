alp = {} -- global variable for my stuff
-- should not be used in modules to avoid cycles or dependency ordering constraints

alp.utils = require("utils")

require("options")
require("mappings")
require("plugins")
require("lsp")
require("private/facebook")



