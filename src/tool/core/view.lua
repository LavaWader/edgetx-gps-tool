-- What to draw for a state: a list of plain draw commands.
--   {op = "text", x, y, s, inv}   {op = "frame", x, y, w, h}
--   {op = "fill", x, y, w, h}     {op = "rects", list = {x, y, w, h, ...}}
-- Text is clipped at 6 px per character (EdgeTX's normal font).
local app = require("tool.core.app")

local M = {}
M.TITLE = "GPS positions"
-- The title takes TOP px (a line of text, a rule under it); then entries of
-- two lines and a 2 px gap, so three fit on a 64 px screen.
local CHAR_W, LINE, ROW, TOP = 6, 8, 18, 10

local STATUS = {pending = "...", reading = "reading...", none = "Not found", error = "Can't read"}

local coords = require("gps.core.fix").text

-- Title and second line of row i (false: single-line row). Logs are
-- numbered from 1, newest first; telemetry isn't.
local function row_text(s, i)
  if i > #s.entries then return "More", false end
  local e = s.entries[i]
  if e.kind == "telemetry" then
    if s.telem then return "Telemetry", coords(s.telem) end
    return "Telemetry", "no GPS fix"
  end
  local title = string.format("%d. %s", i - 1, e.label)
  if e.status == "found" then return title, coords(e.fix) end
  return title, STATUS[e.status]
end

-- The title, then the rows that fit, scrolled to keep the selection on
-- screen. The selected row is a filled bar behind its lines, with the text
-- inverted on it. A note on why there are no logs follows the rows; it can't
-- be selected.
function M.ops(s)
  local chars = math.floor(s.ctx.w / CHAR_W)
  local out = {}
  local function text(y, str, inv)
    if #str > chars then str = string.sub(str, 1, chars) end
    out[#out + 1] = {op = "text", x = 0, y = y, s = str, inv = inv}
  end
  text(0, M.TITLE, false)
  out[#out + 1] = {op = "fill", x = 0, y = LINE, w = s.ctx.w, h = 1}
  local visible = math.floor((s.ctx.h - TOP + ROW - 2 * LINE) / ROW)
  local top = 1
  if s.sel > visible then top = s.sel - visible + 1 end
  local rows = app.rows(s)
  local last = rows
  if s.log_note then last = rows + 1 end
  for i = top, math.min(last, top + visible - 1) do
    local y = TOP + (i - top) * ROW
    local title, line
    if i > rows then title, line = s.log_note[1], s.log_note[2] else title, line = row_text(s, i) end
    local sel = i == s.sel
    if sel then
      local h = LINE
      if line then h = 2 * LINE end
      out[#out + 1] = {op = "fill", x = 0, y = y, w = s.ctx.w, h = h}
    end
    text(y, title, sel)
    if line then text(y + LINE, " " .. line, sel) end
  end
  return out
end

return M
