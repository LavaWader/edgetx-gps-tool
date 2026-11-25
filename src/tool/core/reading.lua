-- The list's I/O results: the log folder listed, a log opened, a chunk read.
-- Called by tool/core/app.lua's update with the result its effect asked for;
-- ships with the log code, so it's only in memory while logs are read.
-- The CSV reader is required where it's used: listing the folder doesn't
-- need it, so the two are never loaded together.
local function scan() return require("gps.core.logscan") end

local with = require("tool.core.app").with

local M = {}

-- A copy of s.entries with entry i replaced.
local function set(s, i, e)
  local list = {}
  for k = 1, #s.entries do list[k] = s.entries[k] end
  list[i] = e
  return list
end

-- Start reading the first pending log, unless one is being read already.
local function next_read(s)
  if s.reading then return s end
  for i = 2, #s.entries do
    local e = s.entries[i]
    if e.status == "pending" then
      local path = s.ctx.cfg.log_dir .. "/" .. e.name
      return with(s, {
        entries = set(s, i, with(e, {status = "reading"})), reading = i, path = path,
        effect = {kind = "open", path = path, head = s.ctx.cfg.header_max},
      })
    end
  end
  return with(s, {effect = false})
end

local function finish(s, status, fix)
  local e = with(s.entries[s.reading], {status = status, fix = fix})
  return next_read(with(s, {entries = set(s, s.reading, e), reading = false,
                                    path = false, scan = false, cols = false, effect = false}))
end

local function continue_scan(s, st)
  if st.found then
    local f = st.found
    return finish(s, "found", {lat = f.lat, lon = f.lon}) -- only what's shown: it's kept
  end
  if st.err then return finish(s, "error", false) end
  if st.done then return finish(s, "none", false) end
  local off, len = scan().request(st)
  return with(s, {scan = st, effect = {kind = "read", path = s.path, offset = off, len = len}})
end

-- No log entries gets a note saying why, so it can be told apart on the radio.
function M.listed(s, m)
  if m.more then return s end -- the same effect again: the next batch
  local dir, files, note = s.ctx.cfg.log_dir, {}, false
  if m.files then
    files = m.files
    if #files == 0 then note = {"No .csv in " .. dir, string.format("%d other files", m.seen or 0)} end -- @mutant no_csv_note: #files == 0 => #files < 0
  elseif m.err == "no_dir" then -- @mutant update_note: m.err == "no_dir" => m.err == "no dir"
    note = {"Logs need EdgeTX 2.9+", "this radio: " .. (m.ver or "older")}
  else
    note = {"Can't list " .. dir, m.err or "?"}
  end
  local list = {s.entries[1]}
  for i = 1, #files do list[i + 1] = {kind = "log", name = files[i], status = "pending", fix = false} end
  return next_read(with(s, {files = files, entries = list, log_note = note, effect = false}))
end

function M.opened(s, m)
  if not m.size or not m.head then return finish(s, "error", false) end
  local cols = require("gps.core.csv").header(m.head)
  if not cols then return finish(s, "none", false) end
  return continue_scan(with(s, {cols = cols}), scan().start(m.size, s.ctx.cfg.chunk))
end

function M.chunk(s, m)
  if not m.text then return finish(s, "error", false) end
  return continue_scan(s, scan().feed(s.scan, m.text, s.cols))
end

return M
