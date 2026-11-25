-- SD card access through the EdgeTX file API. All operations are read-only
-- and idempotent; each opens and closes the file, so nothing is left open.
-- Unverified on a real radio yet (see GROUNDWORK.md, known gaps).
local M = {}

-- The listing in progress: dir()'s iterator and the newest names so far. It
-- stays open between calls, so a big folder is read a batch at a time.
local listing = false

-- The newest max log files in a folder, read at most batch names per call:
-- returns "more" until done, then {list = names newest first, seen = names
-- in the folder}, or nil and why. Only the newest are kept, so the whole
-- listing is never in memory. Why is "no_dir" (plus the firmware version)
-- when the firmware has no dir(): it came in EdgeTX 2.9.
function M.list(path, max, batch)
  if type(dir) ~= "function" then
    local ver = false
    if type(getVersion) == "function" then ver = getVersion() or false end
    return nil, "no_dir", ver
  end
  local files = require("gps.core.logfiles")
  local ok, err = pcall(function()
    if not listing or listing.path ~= path then
      listing = {path = path, it = dir(path), acc = files.newest(max), done = false}
    end
    for _ = 1, batch do
      local name = listing.it()
      if not name then listing.done = true; return end
      files.add(listing.acc, name)
    end
  end)
  if not ok then listing = false; return nil, tostring(err) end
  if not listing.done then return "more" end
  local r = {list = files.result(listing.acc), seen = listing.acc.seen}
  listing = false
  return r
end

-- len bytes starting at offset, or nil when the file can't be opened.
function M.read(path, offset, len)
  local f = io.open(path, "r")
  if not f then return nil end
  if offset > 0 then io.seek(f, offset) end
  local s = io.read(f, len)
  io.close(f)
  return s
end

-- File size and its first n bytes, or nil.
function M.open(path, n)
  if type(fstat) ~= "function" then return nil end
  local info = fstat(path)
  if not info then return nil end
  return info.size, M.read(path, 0, n)
end

return M
