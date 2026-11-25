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
    t.eq(n, 6, "the tool and its five part files")
    t.ok(string.find(string.sub(read(tool(t)), 1, 200), "TNS|", 1, true), "tool name near the start")
  end},

  {"telemetry: the live position, following it; no /LOGS says why", function(t)
    local r = fake.load(tool(t), {gps = {lat = 54.687156, lon = -125.279651}})
    r.init()
    r.run(nil)
    t.ok(r.has_text("Telemetry"), "telemetry row")
    t.ok(r.has_text("54.68716,-125.27965"), "live position, 5 decimals")
    t.ok(r.has_text("Can't list /LOGS"), "says why there are no logs")
    r.gps = {lat = -33.856784, lon = 151.215297}
    r.run(nil)
    t.ok(r.has_text("-33.85678,151.21530"), "follows telemetry")
    r.gps = nil
    r.run(nil)
    t.ok(r.has_text("no GPS fix"), "fix lost")
    t.eq(r.parts(), {"/SCRIPTS/TOOLS/GPStool/ui.lua", "/SCRIPTS/TOOLS/GPStool/uiview.lua"}, "log code freed")
    t.eq(r.run("exit"), 1, "EXIT ends the tool")
    budget(t, r, "telemetry")
  end},

  {"EdgeTX 2.8 (no dir()): asks for an update, telemetry still works", function(t)
    local r = fake.load(tool(t), {gps = {lat = 1.5, lon = 2.5}, firmware = "2.8.4"})
    r.init()
    r.run(nil)
    t.ok(r.has_text("Logs need EdgeTX 2.9+"), "says what to do")
    t.ok(r.has_text("this radio: 2.8.4"), "and what it has")
    t.ok(r.has_text("1.50000,2.50000"), "telemetry")
    t.eq(r.run("exit"), 1)
  end},

  {"logs: newest log read at start, older ones on request", function(t)
    local dir = tmpdir()
    write_log(dir, "Quad-2026-11-20-100000.csv", {'2026-11-20,10:00:00.000,-60,"AIR!",4.1,1.000000 2.000000,9,16.0'})
    local rows = {}
    for i = 1, 30 do
      rows[#rows + 1] = string.format('2026-11-24,09:%02d:00.000,-60,"AIR!",4.1,-33.856784 151.215297,9,16.0', i)
    end
    for i = 1, 600 do -- a minute at 10 Hz without a fix
      rows[#rows + 1] = string.format('2026-11-24,09:59:%02d.%d00,0,"!FS!",0.0,,0,0.0', i % 60, i % 10)
    end
    write_log(dir, "Quad-2026-11-24-090000.csv", rows)
    local r = fake.load(tool(t), {logs_dir = dir})
    r.init()
    r.run(nil)
    t.ok(r.has_text("no GPS fix"), "no telemetry")
    t.ok(r.has_text("1. 11-24 09:00 Quad"), "the newest log only, numbered")
    t.ok(not r.has_text("2. 11-20 10:00 Quad"))
    t.ok(r.idle_until("-33.85678,151.21530", 2000), "its newest fix, past the stretch without one")
    t.eq(r.parts(), {"/SCRIPTS/TOOLS/GPStool/ui.lua", "/SCRIPTS/TOOLS/GPStool/uiview.lua"}, "log code freed once reading is done")
    r.run("next"); r.run("next")
    t.ok(r.has_text("More"))
    r.run("enter")
    t.ok(r.idle_until("1.00000,2.00000", 200), "the older log, read on request")
    t.ok(not r.has_text("More"), "no files left")
    os.execute('rm -rf "' .. dir .. '"')
    budget(t, r, "logs")
  end},
}
