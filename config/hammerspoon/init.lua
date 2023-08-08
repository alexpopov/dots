-- First time notes:
--
-- Install IPC so that the `hs` utility works.
--    Go to the hammerspoon console and type: `hs.ipc.cliInstall()`
--    If this returns false, make sure you pre-create
--    `/usr/local/bin` and `/usr/local/share/man/man1` permissioned to your user:
--
--    sudo mkdir /usr/local/bin /usr/local/share/man/man1
--    sudo chown $USER /usr/local/bin /usr/local/share/man/man1
--
--    If that still fails try uninstalling first: `hs.ipc.cliUninstall()`
--    More info: https://www.hammerspoon.org/docs/hs.ipc.html#cliInstall
require("hs.ipc")

require("hs.application")

alex = require("alex")

function getCurrentApp()
  return hs.application.frontmostApplication()
end

alp = {}
alp.getCurrentApp = function()
  return hs.application.frontmostApplication()
end

alp.actions = {
  chrome = {
    moveTabToNewWindow = function(app)
      app:selectMenuItem({ "Tab", "Move Tab to New Window" })
    end,
  },
}

alp.shortcuts = {
  ["Google Chrome"] = {
    m = alp.actions.chrome.moveTabToNewWindow
  },
}

stackline = require "stackline"
stackline:init({
  paths = {
    yabai = "/opt/homebrew/bin/yabai"
  },
  appearance = {
    radius = 3,
  },
})

