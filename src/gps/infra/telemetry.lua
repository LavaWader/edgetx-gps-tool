-- Reads the GPS telemetry sensor through the EdgeTX API.
-- Contract: read(name) -> getValue() result for the sensor (a {lat, lon}
-- table, or 0), or nil while no sensor with that name exists.
-- Read-only and idempotent; no failure besides "no sensor".
-- EdgeTX keeps the last received value after the link drops.
local M = {}
local id = nil

function M.read(name)
  if not id then
    local info = getFieldInfo(name)
    if not info then return nil end
    id = info.id
  end
  return getValue(id)
end

return M
