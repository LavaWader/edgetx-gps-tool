-- State helpers shared by tool/core/app.lua and tool/core/reading.lua.
local M = {}

-- A copy of s with changes applied (s itself is never modified).
function M.with(s, changes)
  local t = {}
  for k, v in pairs(s) do t[k] = v end
  for k, v in pairs(changes) do t[k] = v end
  return t
end

-- A copy of s.entries with entry i replaced.
function M.set(s, i, e)
  local list = {}
  for k = 1, #s.entries do list[k] = s.entries[k] end
  list[i] = e
  return list
end

-- s with entries for the next k log files.
function M.reveal(s, k)
  local list = {}
  for i = 1, #s.entries do list[i] = s.entries[i] end
  local shown = #list - 1
  for i = shown + 1, math.min(#s.files, shown + k) do
    local f = s.files[i]
    list[#list + 1] = {kind = "log", name = f.name, label = f.label, status = "pending", fix = false}
  end
  return M.with(s, {entries = list})
end

-- Start reading the first pending log, unless one is being read already.
function M.next_read(s)
  if s.reading then return s end
  for i = 2, #s.entries do
    local e = s.entries[i]
    if e.status == "pending" then
      local path = s.ctx.cfg.log_dir .. "/" .. e.name
      return M.with(s, {
        entries = M.set(s, i, M.with(e, {status = "reading"})), reading = i, path = path,
        effect = {kind = "open", path = path, head = s.ctx.cfg.header_max},
      })
    end
  end
  return M.with(s, {effect = false})
end

return M
