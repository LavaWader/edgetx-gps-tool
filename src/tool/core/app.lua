-- The tool as a pure state machine: telemetry, then a "Show 10 last logs"
-- button (cfg.max_files).
-- The SD card isn't touched until it's pressed; then the button gives way
-- to the newest log files, each with its last position.
--
--   local s = M.init(cfg, screen_w, screen_h)
--   s, rejected = M.update(s, msg)
--
-- msg is a tick {kind = "tick", key = "enter"|"exit"|"next"|"prev"|false,
-- telem = <getValue result>} or the result of the I/O call s.effect asked
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

-- A copy of s with changes applied (s itself is never modified).
local function with(s, changes)
  local t = {}
  for k, v in pairs(s) do t[k] = v end
  for k, v in pairs(changes) do t[k] = v end
  return t
end
M.with = with

function M.init(cfg, w, h)
  return {
    ctx = {cfg = cfg, w = w, h = h},
    sel = 1, telem = false,
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

local function key(s, k)
  if k == "next" or k == "prev" then return with(s, {sel = move(s.sel, k, M.rows(s))}) end
  if k == "exit" then return with(s, {quit = true}) end
  -- the button: list the folder, once
  if k == "enter" and s.sel > #s.entries and not s.effect then -- @mutant list_once: and not s.effect then => then
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
    local t = fixes.from_telemetry(m.telem) or false
    if not same_fix(t, s.telem) then s = with(s, {telem = t}) end
    return key(s, m.key)
  end
  if not s.effect or m.kind ~= EXPECT[s.effect.kind] then return s, "stale" end
  s = require("tool.core.reading")[m.kind](s, m)
  -- the button goes once the folder is listed
  if s.sel > M.rows(s) then s = with(s, {sel = M.rows(s)}) end
  return s
end

return M
