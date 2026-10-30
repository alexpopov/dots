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
errorAlert = require("alex.error_alert")

function getCurrentApp()
  return hs.application.frontmostApplication()
end

alp = {}
alp.getCurrentApp = function()
  return hs.application.frontmostApplication()
end

-- The live titles of one top-level menu, e.g. menuTitles(chrome, "Tab").
local function menuTitles(app, menu)
  local found = {}
  for _, m in ipairs(app:getMenuItems() or {}) do
    if m.AXTitle == menu then
      for _, item in ipairs((m.AXChildren or {})[1] or {}) do
        local t = item.AXTitle
        if t and t ~= "" then table.insert(found, t) end
      end
    end
  end
  return found
end

-- Fold away the things vendors change without changing the command: letter
-- case, a trailing ellipsis, and runs of whitespace. Chrome is mid-migration
-- to sentence case, so its Tab menu currently mixes both conventions
-- ("Select Next Tab" next to "Move tab to new window") and the spelling of
-- any given item is not something we should have to track.
local function normalizeTitle(s)
  s = s:lower()
  s = s:gsub("\226\128\166", "")   -- U+2026 HORIZONTAL ELLIPSIS
  s = s:gsub("%.%.%.", "")
  s = s:gsub("%s+", " ")
  s = s:gsub("^ *(.-) *$", "%1")
  return s
end

-- Pick whichever of `titles` actually exists in the app's `menu` right now, and
-- remember it (hs.settings, so it survives a reload) so the next invocation
-- probes the winner first. Menus that get renamed by a UI mode -- rather than
-- removed -- are otherwise a coin flip to hardcode.
--
-- Matching is done against the menu's REAL titles, normalized, rather than by
-- asking findMenuItem for an exact string. Exact matching is how this broke:
-- Chrome restyled "Move Tab to New Window" to "Move tab to new window" and
-- selectMenuItem simply did nothing -- no error, no log, the hotkey just died.
local function selectFirstAvailable(app, menu, titles, cacheKey)
  if app == nil then return nil end

  local actual = menuTitles(app, menu)
  local byNorm = {}
  for _, t in ipairs(actual) do byNorm[normalizeTitle(t)] = t end

  local ordered = {}
  local remembered = cacheKey and hs.settings.get(cacheKey) or nil
  if remembered then table.insert(ordered, remembered) end
  for _, title in ipairs(titles) do
    if title ~= remembered then table.insert(ordered, title) end
  end

  for _, want in ipairs(ordered) do
    local hit = byNorm[normalizeTitle(want)]
    if hit then
      app:selectMenuItem({ menu, hit })
      if cacheKey and hit ~= remembered then hs.settings.set(cacheKey, hit) end
      return hit
    end
  end

  -- Nothing matched: forget the stale pick so we re-probe cleanly next time,
  -- and say what WAS there, so the next restyling is a 5-second fix instead of
  -- another silent dead hotkey.
  if cacheKey then hs.settings.clear(cacheKey) end
  print("selectFirstAvailable: no match in " .. menu .. " menu for: " .. table.concat(titles, ", "))
  if #actual > 0 then
    print("selectFirstAvailable: " .. menu .. " menu actually offers: " .. table.concat(actual, " | "))
  end
  return nil
end

alp.actions = {
  chrome = {
    -- Spelled "Move tab to new window" as of Chrome 142; it was Title Case
    -- until Chrome restyled its menus. selectFirstAvailable normalizes case,
    -- so both spellings resolve and we don't have to chase this again. The
    -- plural variant appears when several tabs are selected.
    moveTabToNewWindow = function(app)
      return selectFirstAvailable(
        app or alp.getCurrentApp(),
        "Tab",
        {
          "Move Tab to New Window",
          "Move Tabs to New Window",
          "Move Tab to Another Window",
        },
        "alp.chrome.moveTabToNewWindow"
      )
    end,

    -- Chrome names this item after the tab strip's orientation: horizontal tabs
    -- get "New tab to the right", vertical tabs get "New tab below". Same
    -- action, so ask for either and cache which one this setup uses. (Case here
    -- is cosmetic -- selectFirstAvailable matches case-insensitively.)
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
