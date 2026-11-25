-- SD card access through the EdgeTX file API. All operations are read-only
-- and idempotent; each opens and closes the file, so nothing is left open.
-- Unverified on a real radio yet (see GROUNDWORK.md, known gaps).
local M = {}

-- File names in a folder, or nil and why. Why is "no_dir" (plus the
-- firmware version) when the firmware has no dir(): it came in EdgeTX 2.9.
function M.list(path)
  if type(dir) ~= "function" then
    local ver = false
    if type(getVersion) == "function" then ver = getVersion() or false end
    return nil, "no_dir", ver
  end
  local ok, names = pcall(function()
    local t = {}
    for name in dir(path) do t[#t + 1] = name end
    return t
  end)
  if ok then return names end
  return nil, tostring(names)
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
