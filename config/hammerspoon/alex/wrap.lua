-- Wrap the selection at 80 columns.
--
-- Replaces the "Wrap @ 80" Automator Quick Action, which was 1.5-2.5s per
-- invocation. None of that was `fold`: Automator cold-starts a Service Runner
-- process, loads Automator.framework, the Run Shell Script action bundle and
-- its nib, just to pipe a string through a command that takes under 5ms.
-- Hammerspoon is already running, so doing it in-process costs a clipboard
-- round-trip (~60ms) and nothing else.

local M = {}

-- `fold -w width -s`: longest prefix that ends on a blank and fits in `width`;
-- if the first `width` columns hold no blank, break hard at `width` (same as
-- fold -- a 200-char URL has to go somewhere). Existing newlines are kept, so
-- paragraphs and blank lines survive.
--
-- Differs from fold -s in one way on purpose: the blank we broke at is dropped
-- rather than left dangling at the end of the line.
function M.fold(text, width)
  width = width or 80
  local out = {}
  for src in (text .. "\n"):gmatch("([^\n]*)\n") do
    local line = src
    while utf8.len(line) and utf8.len(line) > width do
      local cut = utf8.offset(line, width + 1) - 1 -- byte index of column `width`
      local head = line:sub(1, cut)
      local brk = head:find("%s[^%s]*$") -- last blank inside the first `width` cols
      if brk then
        table.insert(out, head:sub(1, brk - 1))
        line = line:sub(brk + 1)
      else
        table.insert(out, head)
        line = line:sub(cut + 1)
      end
    end
    table.insert(out, line)
  end
  return table.concat(out, "\n")
end

-- Copy the selection, fold it, paste it back, restore the old clipboard.
function M.selection(width)
  local saved = hs.pasteboard.getContents()
  local before = hs.pasteboard.changeCount()

  hs.eventtap.keyStroke({ "cmd" }, "c", 0)

  -- Poll instead of sleeping a fixed amount: the app answers in ~10-30ms and
  -- we want the fast case fast, but a slow Electron app gets its 500ms.
  local deadline = hs.timer.absoluteTime() + 500 * 1e6
  while hs.pasteboard.changeCount() == before and hs.timer.absoluteTime() < deadline do
    hs.timer.usleep(5000)
  end
  if hs.pasteboard.changeCount() == before then
    hs.alert.show("Wrap @ " .. (width or 80) .. ": nothing selected")
    return
  end

  hs.pasteboard.setContents(M.fold(hs.pasteboard.getContents() or "", width))
  hs.eventtap.keyStroke({ "cmd" }, "v", 0)

  -- Put the user's clipboard back once the paste has been served.
  hs.timer.doAfter(0.3, function()
    if saved then hs.pasteboard.setContents(saved) end
  end)
end

return M
