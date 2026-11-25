-- How a log file is shown on the list. EdgeTX names logs
-- "<model>-YYYY-MM-DD-HHMMSS.csv" (older: without the time). Worked out when
-- drawn, so the list only keeps file names.
local M = {}

-- "YYYY-MM-DD[ HH:MM:SS]" and the model, or for a name in another shape: itself without ".csv", and "".
function M.lines(name)
  local base = string.gsub(name, "%.[cC][sS][vV]$", "")
  local model, date, rest = string.match(base, "^(.-)%-(%d%d%d%d%-%d%d%-%d%d)(.*)$")
  if not model then return base, "" end
  if rest == "" then return date, model end
  local hh, mm, ss = string.match(rest, "^%-(%d%d)(%d%d)(%d%d)$")
  if not hh then return base, "" end
  return date .. " " .. hh .. ":" .. mm .. ":" .. ss, model -- @mutant seconds: ":" .. ss, model => "", model
end

return M
