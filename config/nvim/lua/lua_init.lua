alp = {} -- global variable for my stuff
-- should not be used in modules to avoid cycles or dependency ordering constraints

alp.utils = require("utils")

require("config.lazy")
require("options")
require("mappings")
require("lsp")
require("globals")

-- Meta-only nvim tooling (the `meta` plugin, task-oil, etc.) loads via
-- lua/plugins/private_meta.lua under $ENABLE_PRIVATE_FACEBOOK. The old
-- `require("private/meta")` here pointed at a lua/private/meta.lua symlink
-- into ~/dotfiles/meta.lua that no longer exists — removed.
