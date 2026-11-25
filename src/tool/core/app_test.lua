local app = require("tool.core.app")
local view = require("tool.core.view")
local fix = require("gps.core.fix")
local logfiles = require("gps.core.logfiles")

local function gen_cfg(rng)
  return {
    gps_sensor = "S",
    log_dir = "/L",
    max_files = rng.int(1, 6),
    list_batch = rng.int(1, 5),
    header_max = 4096,
    chunk = rng.int(1, 64)
  }
end

local function gen_coords(rng) return { lat = rng.float(-90, 90), lon = rng.float(-180, 180) } end

local function gen_log(rng)
  local kind = rng.int(1, 8)
  if kind == 1 then return "" end
  if kind == 2 then return "Date,Time,Sats\n2026-11-24,14:00:00.000,9\n" end
  local lines = { "Date,Time,GPS" }
  for i = 1, rng.int(0, 12) do
    local gps = ""
    if rng.int(1, 3) > 1 then
      local c = gen_coords(rng)
      gps = string.format("%.6f %.6f", c.lat, c.lon)
    end
    lines[#lines + 1] = string.format("2026-11-24,14:%02d:00.000,%s", i, gps)
  end
  return table.concat(lines, "\n") .. "\n"
end

-- A file system for the effects to run against.
local function gen_env(rng)
  local env = { names = {}, files = {}, no_dir = rng.int(1, 10) == 1 }
  for i = 1, rng.int(0, 14) do
    local name = string.format("Quad-2026-11-%02d-1200%02d.csv", rng.int(1, 28), i)
    env.names[#env.names + 1] = name
    env.files[name] = gen_log(rng)
  end
  env.names[#env.names + 1] = "readme.txt"
  return env
end

-- What the glue does for each effect, against the generated file system.
local function perform(env, e)
  if e.kind == "list" then
    if env.no_dir then return { kind = "listed", err = "no such folder" } end
    -- a big folder takes several calls: "more" until every name is read
    env.read = (env.read or 0) + e.batch
    if env.read < #env.names then return { kind = "listed", more = true } end
    local acc = logfiles.newest(e.max)
    for _, n in ipairs(env.names) do logfiles.add(acc, n) end
    return { kind = "listed", files = logfiles.result(acc), seen = #env.names }
  end
  local text = env.files[string.match(e.path, "[^/]+$")]
  if e.kind == "open" then
    if not text then return { kind = "opened" } end
    return { kind = "opened", size = #text, head = string.sub(text, 1, e.head) }
  end
  return { kind = "chunk", text = string.sub(text, e.offset + 1, e.offset + e.len) }
end

-- The drawn text op with this text (leading spaces ignored), or nil.
local function drawn(s, str)
  for _, o in ipairs(view.ops(s)) do
    if o.op == "text" and string.match(o.s, "^ *(.-)$") == str then return o end
  end
end

-- A tick 100 ms after the last one.
local clock = 0
local function tick(s, key, telem)
  clock = clock + 10
  return app.update(s, { kind = "tick", key = key or false, telem = telem or 0, now = clock })
end

-- Feed effects until none is pending (the list's background reading).
local function settle(s, env)
  for _ = 1, 100000 do
    if not s.effect then return s end
    s = app.update(s, perform(env, s.effect))
  end
  error("effects never settle")
end

-- Press "Show logs" (the row after telemetry) and let the reading finish.
local function show_logs(s, env)
  s = tick(s, "next")
  return settle(tick(s, "enter"), env)
end

local function check(t, s, w, h)
  t.ok(s.sel >= 1 and s.sel <= app.rows(s), "selection in range")
  t.eq(s.entries[1].kind, "telemetry", "telemetry first")
  local reading, pending = 0, 0
  for i = 2, #s.entries do
    local e = s.entries[i]
    t.eq(e.name, s.files[i - 1], "entries follow the files, newest first")
    if e.status == "reading" then
      reading = reading + 1; t.eq(s.reading, i, "reading index")
    end
    if e.status == "pending" then pending = pending + 1 end
    if e.status == "found" then t.ok(fix.valid(e.fix.lat, e.fix.lon), "a found fix is valid") end
  end
  t.ok(reading <= 1, "one log at a time")
  t.ok(pending == 0 or reading == 1, "a log waits only while another is read")
  t.ok(not s.telem_wait or s.telem == false, "no position while telemetry is read again")
  t.eq(s.log_note ~= false, s.files ~= false and #s.files == 0, "a note exactly when there are no log entries")
  if s.reading then t.ok(s.effect, "reading only with I/O pending") end
  t.eq(app.needs_logs(s), s.effect ~= false, "log code needed exactly while I/O is pending")
  t.eq(app.needs_listing(s), s.effect ~= false and s.effect.kind == "list", "listing code only while listing")
  t.ok(s.files ~= false or not s.effect or s.effect.kind == "list", "no log opened before the folder is listed")
  t.eq(app.rows(s) > #s.entries, s.files == false, "Show logs until listed, then no button")
  local inv, lines = 0, 1
  if s.sel > 1 and s.sel <= #s.entries then lines = 3 end
  for _, o in ipairs(view.ops(s)) do
    if o.op == "text" and o.inv then inv = inv + 1 end
    if o.op == "text" then
      local cw = view.CHAR_W
      if o.small then cw = view.SMALL_W end
      local th = 8
      if o.small then th = 6 end
      t.ok(o.x >= 0 and o.y >= 0 and o.y + th <= h and o.x + #o.s * cw <= w, "text on screen: " .. o.s)
    else
      t.ok(o.x >= 0 and o.y >= 0 and o.x + o.w <= w and o.y + o.h <= h, o.op .. " on screen")
    end
  end
  t.eq(inv, lines, "the selected row on screen, whole")
end

return {
  { "any sequence of keys, telemetry and I/O results keeps the invariants", function(t)
    local seen = {}
    t.forall(60, function(rng)
      return {
        cfg = gen_cfg(rng),
        env = gen_env(rng),
        w = rng.pick({ 128, 212 }),
        steps = rng.int(50, 400),
        year = rng.pick({ 2026, 2000, 2005, false })
      }
    end, function(c)
      local rng = t.rng
      local s = app.init(c.cfg, c.w, 64, c.year)
      t.eq(s.effect, false, "the card isn't touched at start")
      local raw = 0
      local pressed = false
      for _ = 1, c.steps do
        if s.effect then
          local after, why = app.update(s, perform(c.env, s.effect))
          t.ok(not why, "the pending effect's result is accepted")
          s = after
          check(t, s, c.w, 64)
        end
        local roll = rng.int(1, 10)
        if roll == 1 then
          raw = gen_coords(rng)
        elseif roll == 2 then
          raw = 0
        elseif roll == 3 then
          raw = { lat = 0, lon = 0 }
        end
        local key = false
        if rng.int(1, 4) == 1 then key = rng.pick({ "enter", "next", "prev", "enter", "next", "prev", "exit" }) end
        if key == "enter" and s.files == false and s.sel == app.rows(s) then pressed = true end
        s = tick(s, key, raw)
        if not pressed then t.eq(s.effect, false, "no I/O before Show logs is pressed") end
        for i = 2, #s.entries do seen[s.entries[i].status] = true end
        check(t, s, c.w, 64)
        if key == "exit" then
          t.ok(s.quit, "EXIT quits"); break
        end
        t.ok(not s.quit, "only EXIT quits")
      end
      if not s.quit then
        s = settle(s, c.env)
        for i = 2, #s.entries do
          local st = s.entries[i].status
          t.ok(st == "found" or st == "none" or st == "error", "every shown log gets read")
        end
      end
    end)
    for _, k in ipairs({ "found", "none" }) do t.ok(seen[k], "sequences reach " .. k) end
  end },

  { "startup: telemetry and a Show logs button; logs only when pressed", function(t)
    local env = { names = {}, files = {} }
    for d = 1, 8 do
      local name = string.format("Quad-2026-11-%02d-120000.csv", d)
      env.names[d] = name
      env.files[name] = string.format("Date,Time,GPS\n2026-11-%02d,12:00:01.000,%d.5 %d.5\n", d, d, d)
    end
    local cfg = gen_cfg(t.rng)
    cfg.max_files = 5
    local s = app.init(cfg, 128, 64)
    t.eq(s.effect, false, "nothing read at start")
    t.eq(app.rows(s), 2, "telemetry and the button")
    t.ok(drawn(s, "Telemetry") and drawn(s, "Logs") and drawn(s, "Show 5 last logs"), "two headings, the button")
    t.ok(not drawn(s, "Show 5 last logs").inv, "telemetry selected, not the button")
    s = tick(s, "enter")
    t.eq(s.effect, false, "ENTER on telemetry reads no file")
    for _ = 1, 6 do s = tick(s) end -- past its "reading..."
    s = tick(tick(tick(s, "next"), "next"), "next")
    t.eq(s.sel, 2, "stops at the button")
    s = tick(s, "enter")
    t.eq(s.effect.kind, "list", "the button lists /LOGS")
    t.ok(drawn(s, "Listing logs...").inv, "the button says it's busy")
    t.ok(tick(s, "enter") == s, "pressing again while listing does nothing")
    s = settle(s, env)
    t.eq(#s.entries, 6, "telemetry and the newest five logs")
    t.eq(s.entries[2].name, "Quad-2026-11-08-120000.csv")
    t.eq(s.entries[2].fix.lat, 8.5)
    t.eq(s.entries[6].fix.lat, 4.5)
    t.eq(s.sel, 2, "the selection sits on the newest log")
    t.eq(app.rows(s), 6, "the button is gone")
    s = tick(s, "prev")
    t.eq(s.sel, 1, "stops at the top")
    for _ = 1, 10 do s = tick(s, "next") end
    t.eq(s.sel, 6, "stops at the last log")
    s = tick(s, "enter")
    t.eq(s.entries[6].status, "reading", "ENTER on a log reads it again")
    t.eq(s.entries[6].fix, false, "its old position cleared")
    t.ok(tick(s, "enter") == s, "ENTER again while it's read does nothing")
    s = settle(s, env)
    t.eq(s.entries[6].fix.lat, 4.5, "read again")
  end },

  { "telemetry follows the live value; ENTER shows reading... for a moment", function(t)
    local s = app.init(gen_cfg(t.rng), 128, 64)
    local fix = { lat = 54.687156, lon = 25.279651 }
    s = tick(s, false, fix)
    t.eq(s.telem, { lat = 54.687156, lon = 25.279651 })
    t.ok(drawn(s, "54.68716, 25.27965"), "the live position")
    s = tick(s, "enter", fix)
    t.eq(s.telem, false, "cleared")
    t.ok(drawn(s, "reading...") and not drawn(s, "54.68716, 25.27965"), "reading...")
    t.eq(s.effect, false, "no I/O")
    for _ = 1, 3 do s = tick(s, false, fix) end
    t.ok(drawn(s, "reading..."), "still, 300 ms later")
    for _ = 1, 3 do s = tick(s, false, fix) end
    t.ok(drawn(s, "54.68716, 25.27965") and not drawn(s, "reading..."), "then the live value again")
    s = tick(s, false, 0)
    t.eq(s.telem, false, "no fix, no position")
    s = tick(s, "exit")
    t.ok(s.quit)
  end },

  { "a late I/O result is ignored", function(t)
    local s = show_logs(app.init(gen_cfg(t.rng), 128, 64), { names = {}, files = {} })
    local s2, why = app.update(s, { kind = "chunk", text = "late" })
    t.eq(why, "stale")
    t.ok(s2 == s)
    local fresh = app.init(gen_cfg(t.rng), 128, 64)
    s2, why = app.update(fresh, { kind = "listed", files = {} })
    t.eq(why, "stale", "a listing nobody asked for")
    t.ok(s2 == fresh)
  end },

  { "no log entries: a note says why", function(t)
    local cfg = gen_cfg(t.rng)
    local s = show_logs(app.init(cfg, 128, 64), { names = {}, files = {}, no_dir = true })
    t.eq(s.log_note, { "Can't list /L", "no such folder" })
    t.eq(s.sel, 1, "the button is gone; the selection moves up")
    s = show_logs(app.init(cfg, 128, 64), { names = { "a.txt", "b" }, files = {} })
    t.eq(s.log_note, { "No .csv in /L", "2 other files" })
    local pressed = tick(tick(app.init(cfg, 128, 64), "next"), "enter")
    s = app.update(pressed, { kind = "listed", err = "no_dir", ver = "2.8.4" })
    t.eq(s.log_note, { "Logs need EdgeTX 2.9+", "this radio: 2.8.4" }, "firmware without dir()")
    local ops = view.ops(s)
    t.eq(ops[#ops - 1].s, "Logs need EdgeTX 2.9+", "fits a 128 px line")
    s = app.update(pressed, { kind = "listed", err = "no_dir" })
    t.eq(s.log_note[2], "this radio: older", "version unknown")
    s = show_logs(app.init(cfg, 128, 64), { names = { "a.txt", "b" }, files = {} })
    ops = view.ops(s)
    t.eq(ops[#ops - 1].s, "No .csv in /L")
    t.eq(ops[#ops].s, " 2 other files")
    t.eq(app.rows(s), 1, "the note isn't a row")
  end },

  { "a log's name on two lines: date and time to the second, then the model", function(t)
    local long = "AVeryLongFileNameWithoutAnyDateInIt.csv"
    local env = {
      names = { "MyVeryLongQuad1-2026-11-24-093015.csv", long },
      files = {
        ["MyVeryLongQuad1-2026-11-24-093015.csv"] = "Date,Time,GPS\n", [long] = "Date,Time,GPS\n",
      }
    }
    local cfg = gen_cfg(t.rng)
    cfg.max_files = 5
    local s = tick(show_logs(app.init(cfg, 128, 64), env), "prev")
    t.ok(drawn(s, "1. 2026-11-24 09:30:15").small, "date and time, small font")
    t.ok(drawn(s, "MyVeryLongQuad1").small, "the whole model name under it")
    t.ok(not drawn(s, "No location").small, "the position line in the normal font")
    s = tick(tick(s, "next"), "next")
    t.ok(drawn(s, "2. AVeryLongFileNameWithoutAnyDa"), "another name: the first 32 characters")
    t.ok(drawn(s, "teInIt"), "and the rest on the next line")
  end },

  { "radio clock at 2000-2005 (its battery flat): a warning under Logs, from the start", function(t)
    local cfg = gen_cfg(t.rng)
    cfg.max_files = 5
    t.ok(not drawn(app.init(cfg, 128, 64, 2006), "Warning. Year is 2006"), "clock set: no warning")
    t.ok(not drawn(app.init(cfg, 128, 64, false), "Warning. Year is 2000"), "year unknown: no warning")
    t.ok(drawn(app.init(cfg, 128, 64, 2005), "Warning. Year is 2005"), "2005 is still too early: its year")
    local s = app.init(cfg, 128, 64, 2000)
    local ops = view.ops(s)
    t.eq(ops[7], { op = "text", x = 0, y = 30, s = "Warning. Year is 2000", inv = false, small = false }, "under Logs")
    t.eq(ops[8], { op = "text", x = 0, y = 38, s = " RTC battery is low", inv = false, small = false })
    t.eq(ops[9], { op = "text", x = 0, y = 48, s = "Show 5 last logs", inv = false, small = false }, "then the button")
    local env = { names = { "Quad-2000-01-01-000107.csv" }, files = { ["Quad-2000-01-01-000107.csv"] = "Date,Time,GPS\n" } }
    s = show_logs(s, env)
    t.eq(s.sel, 2, "on the log")
    ops = view.ops(s)
    t.eq(ops[1], { op = "text", x = 0, y = 0, s = "no GPS fix", inv = false, small = false }, "scrolled 10 px")
    t.eq(ops[2], { op = "text", x = 0, y = 10, s = "Logs", inv = false, small = false })
    t.eq(ops[4].s, "Warning. Year is 2000", "the warning still above the log")
    t.ok(drawn(s, "1. 2000-01-01 00:01:07").inv, "the log, with its year")
    t.eq(view.ops(tick(s, "prev"))[1].s, "Telemetry", "back at the top")
  end },

  { "page: two headings, rows under them; the selected row is an inverted bar; it scrolls", function(t)
    local cfg = gen_cfg(t.rng)
    cfg.max_files = 5
    local s = app.init(cfg, 128, 64)
    t.eq(view.ops(s), {
      { op = "text", x = 0, y = 0,  s = "Telemetry",        inv = false, small = false },
      { op = "fill", x = 0, y = 8,  w = 128,                h = 1 },
      { op = "fill", x = 0, y = 10, w = 128,                h = 8 },
      { op = "text", x = 0, y = 10, s = "no GPS fix",       inv = true,  small = false },
      { op = "text", x = 0, y = 20, s = "Logs",             inv = false, small = false },
      { op = "fill", x = 0, y = 28, w = 128,                h = 1 },
      { op = "text", x = 0, y = 30, s = "Show 5 last logs", inv = false, small = false },
    }, "at start")
    local env = { names = {}, files = {} }
    for d = 1, 8 do
      local name = string.format("Quad-2026-11-%02d-120000.csv", d)
      env.names[d] = name
      env.files[name] = "Date,Time,GPS\n"
    end
    s = tick(show_logs(s, env), "prev")
    local ops = view.ops(s)
    t.eq(#ops, 10, "one log under the headings, and the next one's first line")
    t.eq(ops[7], { op = "text", x = 0, y = 30, s = "1. 2026-11-08 12:00:00", inv = false, small = true },
      "logs numbered from 1")
    t.eq(ops[8], { op = "text", x = 0, y = 38, s = " Quad", inv = false, small = true }, "the model under it")
    t.eq(ops[9], { op = "text", x = 0, y = 46, s = "No location", inv = false, small = false })
    t.eq(ops[10], { op = "text", x = 0, y = 56, s = "2. 2026-11-07 12:00:00", inv = false, small = true },
      "part of the next")
    s = tick(s, "next")
    ops = view.ops(s)
    t.eq(ops[6], { op = "fill", x = 0, y = 30, w = 128, h = 24 }, "a bar behind all three lines")
    t.ok(ops[7].inv and ops[8].inv and ops[9].inv and not ops[3].inv, "all inverted, telemetry not")
    for _ = 1, 3 do s = tick(s, "next") end
    t.eq(s.sel, 5)
    ops = view.ops(s)
    t.eq(#ops, 8, "scrolled: headings gone, a log above the selection, part of one below")
    t.eq(ops[1], { op = "text", x = 0, y = 0, s = "3. 2026-11-06 12:00:00", inv = false, small = true })
    t.eq(ops[4], { op = "fill", x = 0, y = 26, w = 128, h = 24 })
    t.eq(ops[5].s, "4. 2026-11-05 12:00:00")
    t.ok(ops[7].inv)
    t.eq(ops[8], { op = "text", x = 0, y = 52, s = "5. 2026-11-04 12:00:00", inv = false, small = true },
      "the next one's first line")
    s = tick(tick(s, "next"), "next")
    t.eq(s.sel, 6, "stops at the last log")
    t.ok(drawn(s, "5. 2026-11-04 12:00:00").inv)
    for _ = 1, 6 do s = tick(s, "prev") end
    t.eq(view.ops(s)[1].s, "Telemetry", "back at the top: the headings again")
  end },
}
