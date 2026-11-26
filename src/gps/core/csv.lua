-- EdgeTX log CSV lines: fields, the header's column positions, and a data
-- row's GPS fix. Used by gps/core/logscan.lua.
local fix = require("gps.core.fix")

local M = {}

-- Plain split that keeps empty fields.
function M.split(s, sep)
  local out, start = {}, 1
  while true do
    local i = string.find(s, sep, start, true)
    if not i then
      out[#out + 1] = string.sub(s, start)
      return out
    end
    out[#out + 1] = string.sub(s, start, i - 1)
    start = i + 1
  end
end

local function trim_cr(s)
  if string.sub(s, -1) == "\r" then return string.sub(s, 1, -2) end
  return s
end

-- The first `upto` fields of a line split at commas, stopping there so a long row costs only what's asked.
function M.fields(line, upto)
  local out, pos = {}, 1
  for n = 1, upto do
    -- EdgeTX quotes text fields ("AIR!") but they hold no commas; quotes are kept
    local c = string.find(line, ",", pos, true)
    if not c then
      out[n] = string.sub(line, pos)
      return out
    end
    out[n] = string.sub(line, pos, c - 1)
    pos = c + 1
  end
  return out
end

-- Column positions from the header, which must be a whole first line.
function M.header(text)
  local nl = string.find(text, "\n", 1, true)
  if not nl then return nil, "no_header" end
  local line = trim_cr(string.sub(text, 1, nl - 1))
  local names = M.fields(line, #line + 1)
  for i = 1, #names do
    if names[i] == "GPS" then return { gps = i } end -- @mutant gps_column: { gps = i } => { gps = i + 1 }
  end
  return nil, "no_gps"
end

-- A data row's fix from its "lat lon" GPS column, or nil (EdgeTX leaves it empty before a fix).
function M.parse_row(line, cols)
  local g = M.fields(trim_cr(line), cols.gps)[cols.gps]
  if not g then return nil end
  local a, b = string.match(g, "^%s*(%S+)%s+(%S+)%s*$")
  local lat, lon = tonumber(a), tonumber(b)
  if not fix.valid(lat, lon) then return nil end
  return fix.new(lat, lon)
end

return M
