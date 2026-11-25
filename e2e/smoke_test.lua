-- The built tool (dist/SCRIPTS) on a fake EdgeTX: press keys, read the
-- screen, and keep every run() call inside a budget.
local fake = require("fake_edgetx")

-- EdgeTX stops a script that runs too many instructions in one call. The real
-- limit isn't confirmed; this is the target.
local MAX_INSTRUCTIONS = 10000
-- Memory, measured on desktop Lua 5.4 (64-bit; the radio's 32-bit Lua 5.2
-- needs less). The original QR script peaked at 93 KB on this measure and
-- crashed the radio; the first version of this tool peaked at 188 KB and took
-- the radio down with its ELRS link. The budget stays far below both.
local MAX_PEAK_KB = 60
-- Memory to compile one shipped file. The original script, which compiled on
-- a Boxer, measures 36 KB; the one-file QR tool measured 90 KB and didn't.
local MAX_COMPILE_KB = 30

local function scripts(t) return t.root .. "/dist/SCRIPTS" end
local function tool(t) return scripts(t) .. "/TOOLS/GPStool.lua" end

local function write_log(dir, name, rows)
  local f = assert(io.open(dir .. "/" .. name, "wb"))
  f:write("Date,Time,1RSS(dB),FM,Alt(m),GPS,Sats,RxBt(V)\n")
  for _, r in ipairs(rows) do f:write(r, "\n") end
  f:close()
end

local function tmpdir()
  local h = io.popen("mktemp -d")
  local d = h:read("*l")
  h:close()
  return d
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

local function budget(t, r, flow)
  t.ok(r.max_instructions <= MAX_INSTRUCTIONS, string.format(
    "at most %d instructions per call, used %d (on %s)", MAX_INSTRUCTIONS, r.max_instructions, r.max_at))
  t.ok(r.max_peak_kb <= MAX_PEAK_KB, string.format(
    "heap peak at most %d KB, reached %.1f (on %s)", MAX_PEAK_KB, r.max_peak_kb, r.peak_at))
  print(string.format("    %s: max %d instructions per call, heap peak %.1f KB, live %.1f KB",
    flow, r.max_instructions, r.max_peak_kb, r.max_kb))
end

return {
  {"every shipped file compiles within the budget", function(t)
    local h = io.popen('find "' .. scripts(t) .. '" -name "*.lua" | sort')
    local n = 0
    for path in h:lines() do
      local src = read(path)
      collectgarbage("collect"); collectgarbage("collect")
      local before = collectgarbage("count")
      collectgarbage("stop")
      local fn, err = load(src, "=" .. path)
      local kb = collectgarbage("count") - before
      collectgarbage("restart")
      t.ok(fn, err)
      t.ok(kb <= MAX_COMPILE_KB, string.format("%s: compiling takes %.1f KB, budget %d", path, kb, MAX_COMPILE_KB))
      print(string.format("    compile %5.1f KB  %s", kb, string.sub(path, #scripts(t) + 2)))
      n = n + 1
    end
    h:close()
    t.eq(n, 8, "the tool and its seven part files")
    t.ok(string.find(string.sub(read(tool(t)), 1, 200), "TNS|", 1, true), "tool name near the start")
    t.ok(string.find(read(tool(t)), "^%-%- GPS tool for EdgeTX, https://github.com/LavaWader/edgetx%-gps%-tool"),
      "the repo in the header comment")
  end},

  {"telemetry: the live position, following it; no /LOGS says why", function(t)
    local r = fake.load(tool(t), {gps = {lat = 54.687156, lon = -125.279651}})
    r.init()
    r.run(nil)
    t.ok(r.has_text("Telemetry"), "telemetry row")
    t.ok(r.has_text("54.68716, -125.27965"), "live position, 5 decimals")
    t.ok(r.has_text("Show 10 last logs"), "a button for the logs")
    t.ok(not r.has_text("Warning. Year is 2000"), "the clock is set: no warning")
    r.gps = {lat = -33.856784, lon = 151.215297}
    r.run(nil)
    t.ok(r.has_text("-33.85678, 151.21530"), "follows telemetry")
    r.run("enter")
    t.ok(r.has_text("reading...") and not r.has_text("-33.85678, 151.21530"), "ENTER: reading...")
    t.ok(r.idle_until("-33.85678, 151.21530", 20), "then the position again")
    r.gps = nil
    r.run(nil)
    t.ok(r.has_text("no GPS fix"), "fix lost")
    t.eq(r.sd_calls, 0, "the SD card isn't touched")
    t.eq(r.loads, {"/SCRIPTS/TOOLS/GPStool/ui.lua", "/SCRIPTS/TOOLS/GPStool/uiview.lua"}, "no log code loaded")
    r.run("next"); r.run("enter")
    t.ok(r.idle_until("Can't list /LOGS", 10), "pressed: says why there are no logs")
    t.eq(r.parts(), {"/SCRIPTS/TOOLS/GPStool/ui.lua", "/SCRIPTS/TOOLS/GPStool/uiview.lua"}, "log code freed")
    t.eq(r.run("exit"), 1, "EXIT ends the tool")
    budget(t, r, "telemetry")
  end},

  {"200 logs on the card: the newest listed, within the budgets", function(t)
    local dir = tmpdir()
    local newest, label = nil, nil
    for i = 1, 200 do -- dates and times spread out, written in no particular order
      local mo, day, hh, mm = 1 + i % 12, 1 + i % 28, i % 24, i % 60
      local stamp = string.format("2026-%02d-%02d-%02d%02d00", mo, day, hh, mm)
      write_log(dir, "Quad-" .. stamp .. ".csv",
        {string.format('2026-01-01,10:00:00.000,-60,"AIR!",4.1,%d.000000 1.000000,9,16.0', i % 80)})
      if not newest or stamp > newest then
        newest, label = stamp, string.format("1. 2026-%02d-%02d %02d:%02d:00", mo, day, hh, mm)
      end
    end
    local r = fake.load(tool(t), {logs_dir = dir})
    r.init()
    r.run(nil)
    r.run("next"); r.run("enter")
    t.ok(r.idle_until(label, 50), "the newest log first: " .. label)
    os.execute('rm -rf "' .. dir .. '"')
    budget(t, r, "200 logs")
  end},

  {"ten logs with long model names, all read: within the budgets", function(t)
    local dir = tmpdir()
    for d = 1, 28 do -- more than the list keeps
      local name = string.format("MyVeryLongQuad1-2026-11-%02d-100000.csv", d)
      write_log(dir, name, {string.format('2026-11-%02d,10:00:00.000,-60,"AIR!",4.1,-33.856784 151.215297,9,16.0', d)})
    end
    local r = fake.load(tool(t), {logs_dir = dir})
    r.init()
    r.run(nil)
    r.run("next"); r.run("enter")
    for _ = 1, 30 do r.run("next") end
    t.ok(r.idle_until("10. 2026-11-19 10:00:00", 50), "ten listed, the tenth newest last")
    t.ok(r.has_text("MyVeryLongQuad1"), "the model name under it")
    t.ok(r.idle_until("-33.85678, 151.21530", 500), "and read")
    t.ok(r.idle_until("-33.85678, 151.21530", 500) and not r.has_text("reading..."), "all read")
    t.ok(not r.has_text("11. 2026-11-18 10:00:00"), "no eleventh")
    os.execute('rm -rf "' .. dir .. '"')
    budget(t, r, "ten logs")
  end},

  {"EdgeTX 2.8 (no dir()): asks for an update, telemetry still works", function(t)
    local r = fake.load(tool(t), {gps = {lat = 1.5, lon = 2.5}, firmware = "2.8.4"})
    r.init()
    r.run(nil)
    r.run("next"); r.run("enter")
    t.ok(r.idle_until("Logs need EdgeTX 2.9+", 10), "says what to do")
    t.ok(r.has_text("this radio: 2.8.4"), "and what it has")
    t.ok(r.has_text("1.50000, 2.50000"), "telemetry")
    t.eq(r.run("exit"), 1)
  end},

  {"logs: shown on request, the newest ten; a reset clock warned about", function(t)
    local dir = tmpdir()
    for d = 13, 23 do -- the oldest has a different position, and isn't listed
      local gps = "5.000000 6.000000"
      if d == 13 then gps = "1.000000 2.000000" end
      local name = string.format("Quad-2026-11-%02d-100000.csv", d)
      write_log(dir, name, {string.format('2026-11-%02d,10:00:00.000,-60,"AIR!",4.1,%s,9,16.0', d, gps)})
    end
    local rows = {}
    for i = 1, 30 do
      rows[#rows + 1] = string.format('2026-11-24,09:%02d:00.000,-60,"AIR!",4.1,-33.856784 151.215297,9,16.0', i)
    end
    for i = 1, 600 do -- a minute at 10 Hz without a fix
      rows[#rows + 1] = string.format('2026-11-24,09:59:%02d.%d00,0,"!FS!",0.0,,0,0.0', i % 60, i % 10)
    end
    write_log(dir, "Quad-2026-11-24-090000.csv", rows)
    local r = fake.load(tool(t), {logs_dir = dir, year = 2000})
    r.init()
    r.run(nil)
    t.ok(r.has_text("no GPS fix"), "no telemetry")
    t.ok(r.has_text("Warning. Year is 2000") and r.has_text("RTC battery is low"), "the clock warning, before any log")
    t.ok(not r.has_text("1. 2026-11-24 09:00:00") and r.sd_calls == 0, "no logs until asked")
    r.run("next"); r.run("enter")
    t.ok(r.idle_until("1. 2026-11-24 09:00:00", 10), "the newest log, numbered, to the second")
    t.ok(r.has_text("Quad"), "the model on the next line")
    t.ok(math.floor(r.text_flags("1. 2026-11-24 09:00:00") / r.SMLSIZE) % 2 == 1, "in the small font")
    t.ok(r.idle_until("-33.85678, 151.21530", 2000), "its newest fix, past the stretch without one")
    for _ = 1, 15 do r.run("next") end
    t.ok(r.idle_until("5.00000, 6.00000", 2000), "the older logs read too")
    t.ok(r.has_text("10. 2026-11-15 10:00:00"), "the tenth is the last")
    for _ = 1, 2000 do -- until every log is read
      if #r.parts() == 2 then break end
      r.run(nil)
    end
    t.eq(r.parts(), {"/SCRIPTS/TOOLS/GPStool/ui.lua", "/SCRIPTS/TOOLS/GPStool/uiview.lua"}, "log code freed once reading is done")
    t.ok(not r.has_text("1.00000, 2.00000") and not r.has_text("11. 2026-11-14 10:00:00"), "the eleventh isn't listed")
    for _ = 1, 15 do r.run("prev") end
    r.run("next")
    r.run("enter")
    t.ok(r.has_text("1. 2026-11-24 09:00:00") and not r.has_text("-33.85678, 151.21530"), "ENTER on a log: read again")
    t.ok(r.idle_until("-33.85678, 151.21530", 2000), "its position again")
    os.execute('rm -rf "' .. dir .. '"')
    budget(t, r, "logs")
  end},
}
