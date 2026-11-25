-- The log file picker's list: CSV files, newest first.
-- EdgeTX names logs "<model>-YYYY-MM-DD-HHMMSS.csv" (older: without the time).
local M = {}

-- Parsed file name, or nil for files that aren't CSV.
function M.entry(name)
  if not string.match(name, "%.[cC][sS][vV]$") then return nil end
  local base = string.sub(name, 1, -5)
  local model, y, mo, d, rest = string.match(base, "^(.-)%-(%d%d%d%d)%-(%d%d)%-(%d%d)(.*)$")
  if not model then return {name = name, stamp = "", label = base} end
  local hh, mm, ss = string.match(rest, "^%-(%d%d)(%d%d)(%d%d)$")
  if not hh then
    if rest ~= "" then return {name = name, stamp = "", label = base} end
    return {name = name, stamp = y .. mo .. d, label = mo .. "-" .. d .. " " .. model}
  end
  return {name = name, stamp = y .. mo .. d .. hh .. mm .. ss,
          label = mo .. "-" .. d .. " " .. hh .. ":" .. mm .. " " .. model}
end

local function newer(a, b)
  if a.stamp ~= b.stamp then return a.stamp > b.stamp end -- @mutant newest_log_first: a.stamp > b.stamp => a.stamp < b.stamp
  return a.name > b.name
end

-- Entries for the CSV files among names, newest first, at most max of them.
-- Files without a date in the name come last. An insertion sort that keeps
-- only the newest max: the radio's Lua has no table library (no table.sort).
function M.sort_desc(names, max)
  local list = {}
  for i = 1, #names do
    local e = M.entry(names[i])
    if e and (#list < max or newer(e, list[#list])) then -- @mutant keep_newest: #list < max or newer(e, list[#list]) => #list < max
      local k = #list
      if k == max then k = k - 1 end -- the oldest drops out
      while k >= 1 and newer(e, list[k]) do
        list[k + 1] = list[k]
        k = k - 1
      end
      list[k + 1] = e
    end
  end
  return list
end

return M
