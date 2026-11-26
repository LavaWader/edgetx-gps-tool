-- The list's I/O results: the log folder listed, a log opened, a chunk read.
-- Called by tool/core/app.lua's update with the result its effect asked for;
-- ships with the log code, so it's only in memory while logs are read.
-- The CSV reader is required where it's used: listing the folder doesn't
-- need it, so the two are never loaded together.
local function scan() return require("gps.core.logscan") end

local queue = require("tool.core.queue")
local with, set, next_read = queue.with, queue.set, queue.next_read

local M = {}

local function finish(s, status, fix)
  local e = with(s.entries[s.reading], { status = status, fix = fix })
  return next_read(with(s, {
    entries = set(s, s.reading, e),
    reading = false,
    path = false,
    scan = false,
    cols = false,
    effect = false
  }))
end

local function continue_scan(s, st)
  if st.found then
    return finish(s, "found", st.found) -- csv.parse_row built it with fix.new
  end
  if st.err then return finish(s, "error", false) end
  if st.done then return finish(s, "none", false) end
  local off, len = scan().request(st)
  return with(s, { scan = st, effect = { kind = "read", path = s.path, offset = off, len = len } })
end

-- No log entries gets a note saying why, so it can be told apart on the radio.
function M.listed(s, m)
  if m.more then return s end -- the same effect again: the next batch
  local dir, files, note = s.ctx.cfg.log_dir, {}, false
  if m.files then
    files = m.files
    if #files == 0 then note = { "No .csv in " .. dir, string.format("%d other files", m.seen or 0) } end -- @mutant no_csv_note: #files == 0 => #files < 0
  elseif m.err == "no_dir" then                                                                           -- @mutant update_note: m.err == "no_dir" => m.err == "no dir"
    note = { "Logs need EdgeTX 2.9+", "this radio: " .. (m.ver or "older") }
  else
    note = { "Can't list " .. dir, m.err or "?" }
  end
  local list = { s.entries[1] }
  for i = 1, #files do list[i + 1] = { kind = "log", name = files[i], status = "pending", fix = false } end
  return next_read(with(s, { files = files, entries = list, log_note = note, effect = false }))
end

function M.opened(s, m)
  if not m.size or not m.head then return finish(s, "error", false) end
  local cols = require("gps.core.csv").header(m.head)
  if not cols then return finish(s, "none", false) end
  return continue_scan(with(s, { cols = cols }), scan().start(m.size, s.ctx.cfg.chunk, s.ctx.cfg.line_max))
end

function M.chunk(s, m)
  if not m.text then return finish(s, "error", false) end
  return continue_scan(s, scan().feed(s.scan, m.text, s.cols))
end

return M
