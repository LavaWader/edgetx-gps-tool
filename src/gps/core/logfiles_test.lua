local logs = require("gps.core.logfiles")

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
  return {names = names, max = rng.int(1, 40)}
end

return {
  {"names: with time, date only, no date, not CSV", function(t)
    t.eq(logs.entry("Quad-2026-11-24-143201.csv"),
      {name = "Quad-2026-11-24-143201.csv", stamp = "20261124143201", label = "11-24 14:32 Quad"})
    t.eq(logs.entry("My-Quad-2026-11-24.csv"),
      {name = "My-Quad-2026-11-24.csv", stamp = "20261124", label = "11-24 My-Quad"})
    t.eq(logs.entry("notes.csv"), {name = "notes.csv", stamp = "", label = "notes"})
    t.eq(logs.entry("photo.jpg"), nil)
  end},

  {"sorted list: only CSVs, newest first, capped, nothing invented", function(t)
    t.forall(300, gen_names, function(c)
      local list = logs.sort_desc(c.names, c.max)
      local csv = 0
      for _, n in ipairs(c.names) do if logs.entry(n) then csv = csv + 1 end end
      t.eq(#list, math.min(csv, c.max), "count")
      for i = 2, #list do
        local a, b = list[i - 1], list[i]
        t.ok(a.stamp > b.stamp or (a.stamp == b.stamp and a.name >= b.name), "order at " .. i)
      end
      local given = {}
      for _, n in ipairs(c.names) do given[n] = true end
      for _, e in ipairs(list) do t.ok(given[e.name], "listed name was given") end
      -- what was left out is no newer than the oldest kept
      local kept = {}
      for _, e in ipairs(list) do kept[e.name] = true end
      local last = list[#list]
      for _, n in ipairs(c.names) do
        local e = logs.entry(n)
        if e and not kept[n] then
          t.ok(last and (e.stamp < last.stamp or (e.stamp == last.stamp and e.name <= last.name)),
            "left out " .. n .. " is older than every kept log")
        end
      end
    end)
  end},
}
