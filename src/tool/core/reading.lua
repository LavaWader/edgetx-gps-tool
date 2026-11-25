-- The list's I/O results: the log folder listed, a log opened, a chunk read.
-- Called by tool/core/app.lua's update with the result its effect asked for;
-- ships with the log code, so it's only in memory while logs are read.
local entries = require("tool.core.entries")
local scan = require("gps.core.logscan")
local logfiles = require("gps.core.logfiles")

local with, set = entries.with, entries.set

local M = {}

local function finish(s, status, fix)
  local e = with(s.entries[s.reading], {status = status, fix = fix})
  return entries.next_read(with(s, {entries = set(s, s.reading, e), reading = false,
                                    path = false, scan = false, cols = false, effect = false}))
end

local function continue_scan(s, st)
  if st.found then
    local f = st.found
    return finish(s, "found", {lat = f.lat, lon = f.lon, time = f.time})
  end
  if st.err then return finish(s, "error", false) end
  if st.done then return finish(s, "none", false) end
  local off, len = scan.request(st)
  return with(s, {scan = st, effect = {kind = "read", path = s.path, offset = off, len = len}})
end

-- No log entries gets a note saying why, so it can be told apart on the radio.
function M.listed(s, m)
  local dir, files, note = s.ctx.cfg.log_dir, {}, false
  if m.names then
    files = logfiles.sort_desc(m.names, s.ctx.cfg.max_files)
    if #files == 0 then note = {"No .csv in " .. dir, string.format("%d other files", #m.names)} end -- @mutant no_csv_note: #files == 0 => #files < 0
  elseif m.err == "no_dir" then -- @mutant update_note: m.err == "no_dir" => m.err == "no dir"
    note = {"Logs need EdgeTX 2.9+", "this radio: " .. (m.ver or "older")}
  else
    note = {"Can't list " .. dir, m.err or "?"}
  end
  return entries.next_read(entries.reveal(with(s, {files = files, log_note = note, effect = false}), 1))
end

function M.opened(s, m)
  if not m.size or not m.head then return finish(s, "error", false) end
  local cols = scan.header(m.head)
  if not cols then return finish(s, "none", false) end
  return continue_scan(with(s, {cols = cols}), scan.start(m.size, s.ctx.cfg.chunk))
end

function M.chunk(s, m)
  if not m.text then return finish(s, "error", false) end
  return continue_scan(s, scan.feed(s.scan, m.text, s.cols))
end

return M
