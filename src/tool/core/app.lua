-- The tool as a pure state machine: one list, telemetry first, then log
-- files, each with its last position.
--
--   local s = M.init(cfg, screen_w, screen_h)
--   s, rejected = M.update(s, msg)
--
-- msg is a tick {kind = "tick", key = "enter"|"exit"|"next"|"prev"|false,
-- telem = <getValue result>} or the result of the I/O call s.effect asked
-- for: {kind = "listed", names, err, ver}, {kind = "opened", size, head}, {kind = "chunk", text}.
-- err "no_dir" means the firmware can't list folders (before EdgeTX 2.9);
-- ver is then the firmware version, when known.
-- The glue performs s.effect (at most one per call) and feeds the result back.
-- A transition that doesn't apply returns the state it was given plus a reason.
--
-- The log code (including the I/O results, tool/core/reading.lua) is
-- required where it's used, never at load time: on the radio it lives in a
-- file loaded on demand, and M.needs_logs(s) says when.
local fixes = require("gps.core.fix")
local entries = require("tool.core.entries")

local with, next_read, reveal = entries.with, entries.next_read, entries.reveal

local M = {}

M.BATCH = 5 -- log entries added by "More"

function M.init(cfg, w, h)
  return {
    ctx = {cfg = cfg, w = w, h = h},
    sel = 1, telem = false,
    files = false,                     -- log files, newest first, once listed
    log_note = false,                  -- why there are no log entries: {title, line}
    entries = {{kind = "telemetry"}},  -- then one {kind = "log", ...} per shown file
    reading = false, path = false, scan = false, cols = false,
    quit = false,
    effect = {kind = "list", dir = cfg.log_dir},
  }
end

function M.has_more(s) return s.files ~= false and #s.entries - 1 < #s.files end

-- Rows on the list: the entries, then "More" (more logs) while files remain.
function M.rows(s)
  if M.has_more(s) then return #s.entries + 1 end
  return #s.entries
end

-- The log code is needed exactly while log I/O is pending.
function M.needs_logs(s) return s.effect ~= false end

local EXPECT = {list = "listed", open = "opened", read = "chunk"}

-- The selection stops at the first and last row; it doesn't wrap around.
local function move(i, key, n)
  if key == "next" then i = i + 1 else i = i - 1 end
  return math.max(1, math.min(n, i)) -- @mutant no_wrap: math.max(1, math.min(n, i)) => (i - 1) % n + 1
end

local function key(s, k)
  if k == "next" or k == "prev" then return with(s, {sel = move(s.sel, k, M.rows(s))}) end
  if k == "exit" then return with(s, {quit = true}) end
  if k == "enter" and s.sel > #s.entries then return next_read(reveal(s, M.BATCH)) end -- @mutant more_row: s.sel > #s.entries => s.sel >= #s.entries
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
  return require("tool.core.reading")[m.kind](s, m)
end

return M
