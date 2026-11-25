-- Reads the GPS telemetry sensor through the EdgeTX API.
local M = {}
local id = nil

-- The sensor's getValue(): a {lat, lon} table or 0, still the last one received after the link drops.
-- idempotent: yes
-- fails: nil while no sensor has that name
-- undo: none, read-only
function M.read(name)
  if not id then
    local info = getFieldInfo(name)
    if not info then return nil end
    id = info.id
  end
  return getValue(id)
end

return M
