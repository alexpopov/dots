require("plugins")
require("options")
require("mappings")
require("lsp")
if os.getenv("ENABLE_PRIVATE_FACEBOOK")
then
  require("private/facebook")
end
