<<<<<<< HEAD
alp = {} -- global variable for my stuff
-- should not be used in modules to avoid cycles or dependency ordering constraints

alp.utils = require("utils")

=======
>>>>>>> 51f3da8 (Lots of changes, added lots of mac-specific stuff)
require("plugins")
require("options")
require("mappings")
require("lsp")
<<<<<<< HEAD

=======
>>>>>>> 51f3da8 (Lots of changes, added lots of mac-specific stuff)
if os.getenv("ENABLE_PRIVATE_FACEBOOK")
then
  require("private/facebook")
end
