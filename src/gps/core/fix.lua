-- A GPS fix: what counts as valid, and how it's shown.
local M = {}

-- A fix value: the one place its shape is built.
function M.new(lat, lon) return { lat = lat, lon = lon } end

-- Valid: real numbers in range, and not exactly 0,0 (what receivers report
-- before they have a fix).
function M.valid(lat, lon)
  if type(lat) ~= "number" or type(lon) ~= "number" then return false end
  if lat ~= lat or lon ~= lon then return false end
  if math.abs(lat) > 90 or math.abs(lon) > 180 then return false end -- @mutant lat_range: math.abs(lat) > 90 => math.abs(lat) >= 90
  return not (lat == 0 and lon == 0)                                 -- @mutant null_island: lat == 0 and lon == 0 => lat == 0 or lon == 0
end

-- EdgeTX's getValue() gives a {lat, lon} table for a GPS sensor, or 0.
function M.from_telemetry(v)
  if type(v) ~= "table" or not M.valid(v.lat, v.lon) then return nil end
  return M.new(v.lat, v.lon)
end

-- "lat, lon" to 5 decimals (about 1 m), at most 21 characters: a 128 px line in the normal font.
function M.text(f) return string.format("%.5f, %.5f", f.lat, f.lon) end

return M
