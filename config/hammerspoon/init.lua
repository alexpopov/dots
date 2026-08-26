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
require("hs.fs")

alex = require("alex")
gridOverlay = require("alex.grid_overlay")
skhdUI = require("alex.skhd_ui")

function getCurrentApp()
  return hs.application.frontmostApplication()
end

alp = {}
alp.getCurrentApp = function()
  return hs.application.frontmostApplication()
end

-- Pick whichever of `titles` actually exists in the app's `menu` right now, and
-- remember it (hs.settings, so it survives a reload) so the next invocation
-- probes the winner first. Menus that get renamed by a UI mode -- rather than
-- removed -- are otherwise a coin flip to hardcode.
local function selectFirstAvailable(app, menu, titles, cacheKey)
  if app == nil then return nil end
  local remembered = cacheKey and hs.settings.get(cacheKey) or nil
  local ordered = {}
  if remembered then table.insert(ordered, remembered) end
  for _, title in ipairs(titles) do
    if title ~= remembered then table.insert(ordered, title) end
  end
  for _, title in ipairs(ordered) do
    if app:findMenuItem({ menu, title }) then
      app:selectMenuItem({ menu, title })
      if cacheKey and title ~= remembered then hs.settings.set(cacheKey, title) end
      return title
    end
  end
  -- Nothing matched: forget the stale pick so we re-probe cleanly next time.
  if cacheKey then hs.settings.clear(cacheKey) end
  print("selectFirstAvailable: no match in " .. menu .. " menu for: " .. table.concat(titles, ", "))
  return nil
end

alp.actions = {
  chrome = {
    moveTabToNewWindow = function(app)
      app:selectMenuItem({ "Tab", "Move Tab to New Window" })
    end,

    -- Chrome names this item after the tab strip's orientation: horizontal tabs
    -- get "New Tab to the Right", vertical tabs get "New Tab Below". Same
    -- action, so ask for either and cache which one this setup uses.
    newTabAfterCurrent = function(app)
      return selectFirstAvailable(
        app or alp.getCurrentApp(),
        "Tab",
        { "New Tab to the Right", "New Tab Below" },
        "alp.chrome.newTabAfterCurrent"
      )
    end,
  },
}

alp.shortcuts = {
  ["Google Chrome"] = {
    m = alp.actions.chrome.moveTabToNewWindow
  },
}


local yabai_path = hs.fnutils.find(
  { "/opt/homebrew/bin/yabai", "/Users/alexpopov/.local/homebrew/bin/yabai", "/Users/alexpopov/homebrew/bin/yabai", "/Users/alexpopov/.local/bin/yabai" },
  function(path) return hs.fs.displayName(path) ~= nil end
) or nil
if yabai_path == nil then
  print("ERROR: Could not find yabai path!")
else
  print("Resolved yabai path to: " .. yabai_path)
end

-- ffs stackline
-- local stackline = require "stackline"
-- stackline:init({
--   paths = {
--     yabai = yabai_path
--   },
--   appearance = {
--     radius = 3,
--   },
-- })
