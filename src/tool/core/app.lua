-- The tool as a pure state machine: telemetry, then a "Show 10 last logs"
-- button (cfg.max_files).
-- The SD card isn't touched until it's pressed; then the button gives way
-- to the newest log files, each with its last position.
--
--   local s = M.init(cfg, screen_w, screen_h)
--   s, rejected = M.update(s, msg)
--
-- msg is a tick {kind = "tick", key = "enter"|"exit"|"next"|"prev"|false,
-- telem = <getValue result>, now = <getTime(): 10 ms steps>} or the result of
-- the I/O call s.effect asked
-- for: {kind = "listed", files, seen, err, ver} (or {kind = "listed", more =
-- true} while a big folder is still being read), {kind = "opened", size, head},
-- {kind = "chunk", text}. files: the names of the newest max_files logs,
-- newest first; seen: names in the folder.
-- err "no_dir" means the firmware can't list folders (before EdgeTX 2.9);
-- ver is then the firmware version, when known.
-- The glue performs s.effect (at most one per call) and feeds the result back.
-- A transition that doesn't apply returns the state it was given plus a reason.
--
-- The log code (including the I/O results, tool/core/reading.lua) is
-- required where it's used, never at load time: on the radio it lives in a
-- file loaded on demand, and M.needs_logs(s) says when.
local fixes = require("gps.core.fix")

local M = {}

-- ENTER on telemetry shows "reading..." this long (getTime() steps of 10 ms)
-- before the live value again: it's read every call, so it would only flash.
M.TELEM_WAIT = 50

-- A copy of s with changes applied (s itself is never modified).
local function with(s, changes)
  local t = {}
  for k, v in pairs(s) do t[k] = v end
  for k, v in pairs(changes) do t[k] = v end
  return t
end
M.with = with

-- A copy of s.entries with entry i replaced.
function M.set(s, i, e)
  local list = {}
  for k = 1, #s.entries do list[k] = s.entries[k] end
  list[i] = e
  return list
end

-- Logs waiting to be read are "pending"; the one being read (one at a time,
-- s.reading) is "reading". This starts the first pending one, unless one is
-- being read already.
-- Here, not with the log code: ENTER on a log needs it, and the log code then
-- loads at the start of the next call (with the I/O), not inside this one.
function M.next_read(s)
  if s.reading then return s end
  for i = 2, #s.entries do
    local e = s.entries[i]
    if e.status == "pending" then
      local path = s.ctx.cfg.log_dir .. "/" .. e.name
      return with(s, {
        entries = M.set(s, i, with(e, {status = "reading"})), reading = i, path = path,
        effect = {kind = "open", path = path, head = s.ctx.cfg.header_max},
      })
    end
  end
  return with(s, {effect = false})
end

-- Read log i again (ENTER on it), unless it's waiting or being read already.
local function reload(s, i)
  local e = s.entries[i]
  if e.status == "reading" or e.status == "pending" then return s end -- @mutant reload_busy: e.status == "reading" or => false and
  return M.next_read(with(s, {entries = M.set(s, i, with(e, {status = "pending", fix = false}))}))
end

function M.init(cfg, w, h)
  return {
    ctx = {cfg = cfg, w = w, h = h},
    sel = 1, telem = false,
    telem_wait = false,                -- after ENTER on telemetry: show it again from this time
    files = false,                     -- log file names, newest first, once listed
    log_note = false,                  -- why there are no log entries: {title, line}
    entries = {{kind = "telemetry"}},  -- then one {kind = "log", ...} per file
    reading = false, path = false, scan = false, cols = false,
    quit = false,
    effect = false,
  }
end

-- Rows on the list: the entries, then the button until the folder is listed.
function M.rows(s)
  if s.files == false then return #s.entries + 1 end
  return #s.entries
end

-- The log code is needed exactly while log I/O is pending.
function M.needs_logs(s) return s.effect ~= false end
-- The folder listing's code, only while it's being read.
function M.needs_listing(s) return s.effect ~= false and s.effect.kind == "list" end

local EXPECT = {list = "listed", open = "opened", read = "chunk"}

-- The selection stops at the first and last row; it doesn't wrap around.
local function move(i, key, n)
  if key == "next" then i = i + 1 else i = i - 1 end
  return math.max(1, math.min(n, i)) -- @mutant no_wrap: math.max(1, math.min(n, i)) => (i - 1) % n + 1
end

-- ENTER reads the selected row again: telemetry, a log, or (the button)
-- lists the folder, once.
local function key(s, k, now)
  if k == "next" or k == "prev" then return with(s, {sel = move(s.sel, k, M.rows(s))}) end
  if k == "exit" then return with(s, {quit = true}) end
  if k ~= "enter" then return s end
  if s.sel == 1 then return with(s, {telem = false, telem_wait = now + M.TELEM_WAIT}) end
  if s.sel <= #s.entries then return reload(s, s.sel) end
  if not s.effect then -- @mutant list_once: if not s.effect then => if true then
    local cfg = s.ctx.cfg
    return with(s, {effect = {kind = "list", dir = cfg.log_dir, max = cfg.max_files, batch = cfg.list_batch}})
  end
  return s
end

local function same_fix(a, b)
  if not a or not b then return a == b end
  return a.lat == b.lat and a.lon == b.lon
end

function M.update(s, m)
  if m.kind == "tick" then
    if s.telem_wait and m.now < s.telem_wait then return key(s, m.key, m.now) end -- @mutant telem_hold: m.now < s.telem_wait => m.now > s.telem_wait
    local t = fixes.from_telemetry(m.telem) or false
    if s.telem_wait or not same_fix(t, s.telem) then s = with(s, {telem = t, telem_wait = false}) end
    return key(s, m.key, m.now)
  end
  if not s.effect or m.kind ~= EXPECT[s.effect.kind] then return s, "stale" end
  s = require("tool.core.reading")[m.kind](s, m)
  -- the button goes once the folder is listed
  if s.sel > M.rows(s) then s = with(s, {sel = M.rows(s)}) end
  return s
end

return M
