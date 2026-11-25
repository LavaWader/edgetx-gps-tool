local app = require("tool.core.app")
local view = require("tool.core.view")
local fix = require("gps.core.fix")

local function gen_cfg(rng)
  return {gps_sensor = "S", log_dir = "/L", max_files = rng.int(1, 14), header_max = 4096, chunk = rng.int(1, 64)}
end

local function gen_coords(rng) return {lat = rng.float(-90, 90), lon = rng.float(-180, 180)} end

local function gen_log(rng)
  local kind = rng.int(1, 8)
  if kind == 1 then return "" end
  if kind == 2 then return "Date,Time,Sats\n2026-11-24,14:00:00.000,9\n" end
  local lines = {"Date,Time,GPS"}
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
  local env = {names = {}, files = {}, no_dir = rng.int(1, 10) == 1}
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
    if env.no_dir then return {kind = "listed", err = "no such folder"} end
    return {kind = "listed", names = env.names}
  end
  local text = env.files[string.match(e.path, "[^/]+$")]
  if e.kind == "open" then
    if not text then return {kind = "opened"} end
    return {kind = "opened", size = #text, head = string.sub(text, 1, e.head)}
  end
  return {kind = "chunk", text = string.sub(text, e.offset + 1, e.offset + e.len)}
end

local function tick(s, key, telem) return app.update(s, {kind = "tick", key = key or false, telem = telem or 0}) end

-- Feed effects until none is pending (the list's background reading).
local function settle(s, env)
  for _ = 1, 100000 do
    if not s.effect then return s end
    s = app.update(s, perform(env, s.effect))
  end
  error("effects never settle")
end

local function check(t, s, w, h)
  t.ok(s.sel >= 1 and s.sel <= app.rows(s), "selection in range")
  t.eq(s.entries[1].kind, "telemetry", "telemetry first")
  local reading = 0
  for i = 2, #s.entries do
    local e = s.entries[i]
    t.eq(e.name, s.files[i - 1].name, "entries follow the files, newest first")
    if e.status == "reading" then reading = reading + 1; t.eq(s.reading, i, "reading index") end
    if e.status == "found" then t.ok(fix.valid(e.fix.lat, e.fix.lon), "a found fix is valid") end
  end
  t.ok(reading <= 1, "one log at a time")
  t.eq(s.log_note ~= false, s.files ~= false and #s.files == 0, "a note exactly when there are no log entries")
  if reading == 1 then t.ok(s.effect, "reading only with I/O pending") end
  t.eq(app.needs_logs(s), s.effect ~= false, "log code needed exactly while I/O is pending")
  for _, o in ipairs(view.ops(s)) do
    if o.op == "text" then
      t.ok(o.x >= 0 and o.y >= 0 and o.y + 8 <= h and o.x + #o.s * 6 <= w, "text on screen: " .. o.s)
    else
      t.ok(o.x >= 0 and o.y >= 0 and o.x + o.w <= w and o.y + o.h <= h, o.op .. " on screen")
    end
  end
end

return {
  {"any sequence of keys, telemetry and I/O results keeps the invariants", function(t)
    local seen = {}
    t.forall(60, function(rng)
      return {cfg = gen_cfg(rng), env = gen_env(rng), w = rng.pick({128, 212}), steps = rng.int(50, 400)}
    end, function(c)
      local rng = t.rng
      local s = app.init(c.cfg, c.w, 64)
      local raw = 0
      for _ = 1, c.steps do
        if s.effect then
          local after, why = app.update(s, perform(c.env, s.effect))
          t.ok(not why, "the pending effect's result is accepted")
          s = after
          check(t, s, c.w, 64)
        end
        local roll = rng.int(1, 10)
        if roll == 1 then raw = gen_coords(rng)
        elseif roll == 2 then raw = 0
        elseif roll == 3 then raw = {lat = 0, lon = 0} end
        local key = false
        if rng.int(1, 4) == 1 then key = rng.pick({"enter", "next", "prev", "enter", "next", "prev", "exit"}) end
        s = tick(s, key, raw)
        for i = 2, #s.entries do seen[s.entries[i].status] = true end
        check(t, s, c.w, 64)
        if key == "exit" then t.ok(s.quit, "EXIT quits"); break end
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
    for _, k in ipairs({"found", "none"}) do t.ok(seen[k], "sequences reach " .. k) end
  end},

  {"startup: newest log read in the background, then more on request", function(t)
    local env = {names = {}, files = {}}
    for d = 1, 8 do
      local name = string.format("Quad-2026-11-%02d-120000.csv", d)
      env.names[d] = name
      env.files[name] = string.format("Date,Time,GPS\n2026-11-%02d,12:00:01.000,%d.5 %d.5\n", d, d, d)
    end
    local cfg = gen_cfg(t.rng)
    cfg.max_files = 60
    local s = app.init(cfg, 128, 64)
    t.eq(s.effect.kind, "list", "lists /LOGS first")
    s = settle(s, env)
    t.eq(#s.entries, 2, "telemetry and the newest log")
    t.eq(s.entries[2].name, "Quad-2026-11-08-120000.csv")
    t.eq(s.entries[2].fix.lat, 8.5)
    t.eq(s.entries[2].fix.time, "12:00:01.000")
    t.eq(app.rows(s), 3, "plus More")
    s = tick(s, "prev")
    t.eq(s.sel, 1, "stops at the top")
    s = tick(tick(tick(s, "next"), "next"), "next")
    t.eq(s.sel, 3, "stops at More")
    s = settle(tick(s, "enter"), env)
    t.eq(#s.entries, 2 + app.BATCH)
    t.eq(s.entries[7].fix.lat, 3.5, "next five, newest first")
    t.eq(s.sel, 3, "the selection now sits on the first added entry")
    for _ = 1, 10 do s = tick(s, "next") end
    t.eq(s.sel, 8, "stops at More again")
    s = settle(tick(s, "enter"), env)
    t.eq(#s.entries, 9)
    t.eq(app.rows(s), 9, "no more files, no more row")
    t.eq(s.sel, 8, "selection kept")
  end},

  {"ENTER on an entry changes nothing; telemetry follows the live value", function(t)
    local s = settle(app.init(gen_cfg(t.rng), 128, 64), {names = {}, files = {}})
    local s2 = tick(s, "enter", 0)
    t.ok(s2 == s, "unchanged")
    s = tick(s, false, {lat = 54.687156, lon = 25.279651})
    t.eq(s.telem, {lat = 54.687156, lon = 25.279651})
    t.eq(view.ops(s)[5].s, " 54.68716,25.27965")
    s = tick(s, false, 0)
    t.eq(s.telem, false, "no fix, no position")
    s = tick(s, "exit")
    t.ok(s.quit)
  end},

  {"a late I/O result is ignored", function(t)
    local s = settle(app.init(gen_cfg(t.rng), 128, 64), {names = {}, files = {}})
    local s2, why = app.update(s, {kind = "chunk", text = "late"})
    t.eq(why, "stale")
    t.ok(s2 == s)
  end},

  {"no log entries: a note says why", function(t)
    local cfg = gen_cfg(t.rng)
    local s = settle(app.init(cfg, 128, 64), {names = {}, files = {}, no_dir = true})
    t.eq(s.log_note, {"Can't list /L", "no such folder"})
    s = settle(app.init(cfg, 128, 64), {names = {"a.txt", "b"}, files = {}})
    t.eq(s.log_note, {"No .csv in /L", "2 other files"})
    s = app.update(app.init(cfg, 128, 64), {kind = "listed", err = "no_dir", ver = "2.8.4"})
    t.eq(s.log_note, {"Logs need EdgeTX 2.9+", "this radio: 2.8.4"}, "firmware without dir()")
    local ops = view.ops(s)
    t.eq(ops[#ops - 1].s, "Logs need EdgeTX 2.9+", "fits a 128 px line")
    s = app.update(app.init(cfg, 128, 64), {kind = "listed", err = "no_dir"})
    t.eq(s.log_note[2], "this radio: older", "version unknown")
    s = settle(app.init(cfg, 128, 64), {names = {"a.txt", "b"}, files = {}})
    ops = view.ops(s)
    t.eq(ops[#ops - 1].s, "No .csv in /L")
    t.eq(ops[#ops].s, " 2 other files")
    t.eq(app.rows(s), 1, "the note isn't a row")
  end},

  {"list view: selected entry is one inverted two-line bar; rows scroll", function(t)
    local env = {names = {}, files = {}}
    for d = 1, 8 do
      local name = string.format("Quad-2026-11-%02d-120000.csv", d)
      env.names[d] = name
      env.files[name] = "Date,Time,GPS\n"
    end
    local cfg = gen_cfg(t.rng)
    cfg.max_files = 60
    local s = settle(app.init(cfg, 128, 64), env)
    local ops = view.ops(s)
    t.eq(ops[1], {op = "text", x = 0, y = 0, s = view.TITLE, inv = false}, "title")
    t.eq(ops[2], {op = "fill", x = 0, y = 8, w = 128, h = 1}, "a rule under it")
    t.eq(ops[3], {op = "fill", x = 0, y = 10, w = 128, h = 16}, "a bar behind both lines")
    t.eq(ops[4].s, "Telemetry", "not numbered")
    t.ok(ops[4].inv and ops[5].inv, "both lines inverted")
    t.eq(ops[5].y, 18)
    t.eq(ops[6].y, 28, "next entry after a gap")
    t.eq(ops[6].s, "1. 11-08 12:00 Quad", "logs numbered from 1")
    t.ok(not ops[6].inv)
    t.eq(ops[7].s, " Not found")
    t.eq(ops[8].s, "More")
    s = settle(tick(tick(tick(s, "next"), "next"), "enter"), env)
    t.eq(s.sel, 3, "on the first added log")
    s = tick(tick(s, "next"), "next")
    ops = view.ops(s)
    t.eq(s.sel, 5)
    t.eq(ops[#ops - 1].y, 46, "the selection scrolls into the last slot")
    t.eq(ops[#ops - 1].s, "4. 11-05 12:00 Quad")
    t.ok(ops[#ops].inv)
    t.eq(ops[#ops - 2], {op = "fill", x = 0, y = 46, w = 128, h = 16})
    t.eq(ops[3].s, "2. 11-07 12:00 Quad", "scrolled: the top entry is the one before")
  end},
}
