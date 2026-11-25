-- The log list's files: the names of the newest CSV files, newest first.
-- EdgeTX names logs "<model>-YYYY-MM-DD-HHMMSS.csv" (older: without the time).
local M = {}

-- Sort key of a log name: "YYYYMMDD[HHMMSS]", "" without a date, or nil
-- for files that aren't CSV.
function M.stamp(name)
  if not string.match(name, "%.[cC][sS][vV]$") then return nil end
  local y, mo, d, rest = string.match(name, "%-(%d%d%d%d)%-(%d%d)%-(%d%d)(.-)%.[cC][sS][vV]$")
  if not y then return "" end
  if rest == "" then return y .. mo .. d end
  local hms = string.match(rest, "^%-(%d%d%d%d%d%d)$")
  if not hms then return "" end
  return y .. mo .. d .. hms
end

local function newer(a, b)
  if a.stamp ~= b.stamp then return a.stamp > b.stamp end -- @mutant newest_log_first: a.stamp > b.stamp => a.stamp < b.stamp
  return a.name > b.name
end

-- The newest CSV files among names fed one at a time, so a folder listing
-- never has to be held whole:
--   local acc = M.newest(max)
--   for name in dir(path) do M.add(acc, name) end
--   M.result(acc)  -- names, newest first, at most max; acc.seen: names fed
-- Files without a date in the name come last. An insertion into the few
-- kept (the radio's Lua has no table.sort). acc is changed in place: it's a
-- fresh accumulator only its caller holds (see GROUNDWORK.md).
function M.newest(max) return { list = {}, max = max, seen = 0 } end

function M.add(acc, name)
  acc.seen = acc.seen + 1
  local st = M.stamp(name)
  if not st then return acc end
  local list, e = acc.list, { name = name, stamp = st }
  local k = #list
  if k == acc.max then                           -- full: the oldest drops out, unless this is older still
    if not newer(e, list[k]) then return acc end -- @mutant keep_newest: not newer(e, list[k]) => false
    k = k - 1
  end
  while k >= 1 and newer(e, list[k]) do
    list[k + 1] = list[k]
    k = k - 1
  end
  list[k + 1] = e
  return acc
end

-- The kept names, newest first.
function M.result(acc)
  local out = {}
  for i = 1, #acc.list do out[i] = acc.list[i].name end
  return out
end

return M
