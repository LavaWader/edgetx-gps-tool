-- How a log file is shown on the list. EdgeTX names logs
-- "<model>-YYYY-MM-DD-HHMMSS.csv" (older: without the time). Worked out when
-- drawn, so the list only keeps file names.
local M = {}

-- Two lines: "MM-DD HH:MM:SS" (or "MM-DD") and the model name. A name in
-- another shape is the first line as is (without ".csv"), the second empty.
function M.lines(name)
  local base = string.gsub(name, "%.[cC][sS][vV]$", "")
  local model, mo, d, rest = string.match(base, "^(.-)%-%d%d%d%d%-(%d%d)%-(%d%d)(.*)$")
  if not model then return base, "" end
  if rest == "" then return mo .. "-" .. d, model end
  local hh, mm, ss = string.match(rest, "^%-(%d%d)(%d%d)(%d%d)$")
  if not hh then return base, "" end
  return mo .. "-" .. d .. " " .. hh .. ":" .. mm .. ":" .. ss, model -- @mutant seconds: ":" .. ss, model => "", model
end

return M
