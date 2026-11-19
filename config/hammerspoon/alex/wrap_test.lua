-- Self-check for the folding logic: `lua wrap_test.lua` (no Hammerspoon needed).
package.path = (arg[0]:match("(.*/)") or "./") .. "?.lua;" .. package.path
local fold = dofile((arg[0]:match("(.*/)") or "./") .. "wrap.lua").fold

local function eq(got, want, what)
  assert(got == want, what .. "\n got: " .. got:gsub("\n", "\\n") .. "\nwant: " .. want:gsub("\n", "\\n"))
end

eq(fold("aaa bbb", 80), "aaa bbb", "short line untouched")
eq(fold("aaaa bbbb cccc", 10), "aaaa bbbb\ncccc", "breaks at last blank that fits")
eq(fold("aaaaaaaaaaaa", 5), "aaaaa\naaaaa\naa", "hard-breaks an unbreakable word, like fold")
eq(fold("ab cd\n\nef gh", 80), "ab cd\n\nef gh", "existing newlines and blank lines survive")
eq(fold("aaaa bbbb cccc dddd", 10), "aaaa bbbb\ncccc dddd", "wraps repeatedly")
eq(fold("ééééé ééééé", 7), "ééééé\nééééé", "counts characters, not bytes")
eq(fold("", 80), "", "empty input")

print("ok")
