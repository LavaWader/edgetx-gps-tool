local logs = require("gps.core.logfiles")
local logname = require("gps.core.logname")

local function gen_names(rng)
  local names = {}
  for i = 1, rng.int(0, 30) do
    local kind = rng.int(1, 5)
    local model = rng.pick({"Quad", "Model01", "Wing-2", "a"})
    local date = string.format("%04d-%02d-%02d", rng.int(2020, 2027), rng.int(1, 12), rng.int(1, 28))
    if kind <= 2 then
      names[i] = string.format("%s-%s-%02d%02d%02d.csv", model, date, rng.int(0, 23), rng.int(0, 59), rng.int(0, 59))
    elseif kind == 3 then names[i] = model .. "-" .. date .. ".CSV"
    elseif kind == 4 then names[i] = model .. rng.int(1, 9) .. ".csv"
    else names[i] = model .. ".txt" end
  end
  return {names = names, max = rng.int(1, 8)}
end

local function newest(names, max)
  local acc = logs.newest(max)
  for _, n in ipairs(names) do logs.add(acc, n) end
  return acc
end

-- a is listed before b: newer, or as new and later by name.
local function before(a, b)
  local sa, sb = logs.stamp(a), logs.stamp(b)
  return sa > sb or (sa == sb and a >= b)
end

return {
  {"names: with time, date only, no date, not CSV", function(t)
    t.eq(logs.stamp("Quad-2026-11-24-143201.csv"), "20261124143201")
    t.eq({logname.lines("Quad-2026-11-24-143201.csv")}, {"11-24 14:32:01", "Quad"}, "seconds shown")
    t.eq(logs.stamp("My-Quad-2026-11-24.csv"), "20261124")
    t.eq({logname.lines("My-Quad-2026-11-24.csv")}, {"11-24", "My-Quad"})
    t.eq(logs.stamp("notes.csv"), "")
    t.eq({logname.lines("notes.csv")}, {"notes", ""})
    t.eq({logname.lines("Quad-2026-11-24-1432.csv")}, {"Quad-2026-11-24-1432", ""}, "odd time: the name as is")
    t.eq(logs.stamp("photo.jpg"), nil)
  end},

  {"newest list: only CSVs, newest first, capped, nothing invented, every name counted", function(t)
    t.forall(400, gen_names, function(c)
      local acc = newest(c.names, c.max)
      local list = logs.result(acc)
      t.eq(acc.seen, #c.names, "every name counted")
      local csv = 0
      for _, n in ipairs(c.names) do if logs.stamp(n) then csv = csv + 1 end end
      t.eq(#list, math.min(csv, c.max), "count")
      for i = 2, #list do t.ok(before(list[i - 1], list[i]), "order at " .. i) end
      local given = {}
      for _, n in ipairs(c.names) do given[n] = true end
      for _, n in ipairs(list) do t.ok(given[n], "listed name was given") end
      -- what was left out is no newer than the oldest kept
      local kept = {}
      for _, n in ipairs(list) do kept[n] = true end
      local last = list[#list]
      for _, n in ipairs(c.names) do
        if logs.stamp(n) and not kept[n] then
          t.ok(last and before(last, n), "left out " .. n .. " is older than every kept log")
        end
      end
    end)
  end},
}
