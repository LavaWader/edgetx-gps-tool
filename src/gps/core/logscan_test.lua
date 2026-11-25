local scan = require("gps.core.logscan")
local fix = require("gps.core.fix")
local csv = require("gps.core.csv")

-- A text field the way EdgeTX writes one: sometimes quoted, like the flight
-- mode ("AIR!"). EdgeTX's text values hold no commas or quotes.
local function quote(v, rng)
  if rng.int(1, 4) == 1 then return '"' .. v .. '"' end
  return v
end

local function random_text(rng)
  local chars = {"a", "Z", "!", " ", "1", "-"}
  local b = {}
  for i = 1, rng.int(0, 6) do b[i] = rng.pick(chars) end
  return table.concat(b)
end

-- A random log, generated row by row so the expected answer is known without
-- parsing anything: header with the columns in random order, rows whose GPS
-- field is a fix, empty, 0 0 or garbage, quoted text fields,
-- sometimes \r\n line ends, and sometimes a last row still being written.
local function gen_log(rng)
  local names = {"Date", "Time", "GPS", "FM", "1RSS(dB)", "Sats", "Alt(m)", "Alt(m)"}
  for i = #names, 2, -1 do
    local j = rng.int(1, i)
    names[i], names[j] = names[j], names[i]
  end
  local eol = "\n"
  if rng.int(1, 4) == 1 then eol = "\r\n" end
  local lines, expected = {table.concat(names, ",")}, false
  for r = 1, rng.int(0, 40) do
    local row, gps = {}, ""
    local kind = rng.int(1, 5)
    if kind <= 2 then
      local lat, lon = rng.float(-90, 90), rng.float(-180, 180)
      gps = string.format("%.6f %.6f", lat, lon)
      lat, lon = tonumber(string.format("%.6f", lat)), tonumber(string.format("%.6f", lon))
      if fix.valid(lat, lon) then
        expected = {lat = lat, lon = lon}
      end
    elseif kind == 4 then gps = "0.000000 0.000000"
    elseif kind == 5 then gps = "garbage" end
    for i, name in ipairs(names) do
      if name == "GPS" then row[i] = gps
      elseif name == "Date" then row[i] = "2026-11-24"
      elseif name == "Time" then row[i] = string.format("14:00:%02d.000", r % 60)
      else row[i] = quote(random_text(rng), rng) end
    end
    lines[#lines + 1] = table.concat(row, ",")
  end
  local text = table.concat(lines, eol) .. eol
  if rng.bool() then
    -- a row being written: cut short, so it must not count even if it parses
    local row = {}
    for i, name in ipairs(names) do
      if name == "GPS" then row[i] = "12.345678 23.456789" else row[i] = "1" end
    end
    local full = table.concat(row, ",")
    text = text .. string.sub(full, 1, rng.int(1, #full))
  end
  return {text = text, chunk = rng.int(1, 80), expected = expected}
end

local function run(text, chunk, cols)
  local st = scan.start(#text, chunk)
  local reads = 0
  while not st.done do
    local off, len = scan.request(st)
    st = scan.feed(st, string.sub(text, off + 1, off + len), cols)
    reads = reads + 1
  end
  return st, reads
end

return {
  {"fields: split at commas, empty ones kept, quotes kept, stops early", function(t)
    t.forall(400, function(rng)
      local vals = {}
      for i = 1, rng.int(1, 10) do vals[i] = quote(random_text(rng), rng) end
      return {vals = vals, line = table.concat(vals, ",")}
    end, function(c)
      t.eq(csv.fields(c.line, #c.vals), c.vals, "all fields")
      t.eq(csv.fields(c.line, 1), {c.vals[1]}, "stops early")
    end)
  end},

  {"header: finds the columns, needs a full first line", function(t)
    t.eq(csv.header("Date,Time,GPS,Sats\n2026"), {gps = 3})
    t.eq(csv.header("Time,Sats,GPS\r\n"), {gps = 3})
    local cols, why = csv.header("Date,Time,Sats\n")
    t.eq(cols, nil)
    t.eq(why, "no_gps")
    cols, why = csv.header("Date,Time,GPS")
    t.eq(why, "no_header")
  end},

  {"rows in the shape EdgeTX 2.10 writes (from a real log, coordinates moved)", function(t)
    local head = "Date,Time,1RSS(dB),2RSS(dB),RQly(%),RSNR(dB),ANT,RFMD,TPWR(mW),TRSS(dB),TQly(%),"
      .. "TSNR(dB),FM,VSpd(m/s),Alt(m),GPS,GSpd(kmh),Hdg(\194\176),Alt(m),Sats,RxBt(V),Curr(A),Capa(mAh)\n"
    local cols = csv.header(head)
    t.eq(cols.gps, 16)
    local nofix = '2000-01-01,01:31:48.870,0,0,0,0,0,0,0,0,0,0,"",0.0,0.0,,0.0,0.00,0,0,0.0,0.0,0'
    local withfix = '2000-01-01,01:32:47.840,-10,-7,100,12,1,2,500,-13,88,13,"AIR!",0.0,4.1,'
      .. '12.345678 -98.765432,5.7,84.90,195,6,23.1,0.2,11'
    t.eq(csv.parse_row(nofix, cols), nil, "empty GPS field before the fix")
    t.eq(csv.parse_row(withfix, cols),
      {lat = 12.345678, lon = -98.765432})
    local st = run(head .. nofix .. "\n" .. withfix .. "\n" .. nofix .. "\n", 100, cols)
    t.eq(st.found, {lat = 12.345678, lon = -98.765432}, "the fix before the link dropped")
  end},

  {"scanning backwards in any chunk size finds the newest complete valid row", function(t)
    t.forall(400, gen_log, function(c)
      local cols = csv.header(c.text)
      local st = run(c.text, c.chunk, cols)
      t.eq(st.found, c.expected)
      t.eq(st.err, false)
    end)
  end},

  {"a valid newest row is found in the first read when the chunk holds it", function(t)
    local text = "Date,Time,GPS\n2026-11-24,14:00:00.000,1.5 2.5\n2026-11-24,14:00:01.000,3.5 4.5\n"
    local st, reads = run(text, 64, csv.header(text))
    t.eq(st.found.lat, 3.5)
    t.eq(reads, 1)
  end},

  {"a short read stops the scan with an error", function(t)
    local st = scan.feed(scan.start(100, 10), "short", {gps = 1, last = 1})
    t.ok(st.done and st.err == "short_read")
  end},

  {"an empty file is done at once with nothing found", function(t)
    local st = scan.start(0, 10)
    t.ok(st.done and not st.found)
  end},
}
