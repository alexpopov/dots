M = {}
M._my_name = "alex"

M.test = function()
  return "hello, world!"
end

M.unload = function()
  for l in pairs(package.loaded) do
    if l == M._my_name then
      package.loaded[l] = nil
    end
  end
end

local min=math.min
local max = math.max
local ceil = math.ceil
local abs= math.abs
local fmod= math.fmod
local floor= math.floor
local random= math.random
local next, type, ipairs, pairs, sformat, supper, ssub, tostring=next, type, ipairs, pairs, string.format, string.upper, string.sub, tostring
local tinsert, tremove, tsort, setmetatable, rawset=table.insert, table.remove, table.sort, setmetatable, rawset

return M
