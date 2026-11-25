-- What to draw for a state: a list of plain draw commands.
--   {op = "text", x, y, s, inv, small}   {op = "fill", x, y, w, h}
-- Text is clipped to the screen width: 6 px per character in EdgeTX's normal
-- font (21 on 128 px), 4 px in the small one (32), used for log names.
--
-- One page, scrolled to keep the selected row on screen:
--   Telemetry            heading, a rule under it
--   54.68716, 25.27965   row 1
--   Logs                 heading
--   Show 10 last logs    the button (max_files), until the logs are listed
--   1. 11-24 09:00:15    a log: date and time, model (small font),
--    Quad                then its position
--   54.68716, 25.27965
local app = require("tool.core.app")

local M = {}
-- Lines are 8 px apart; text is 8 px tall in the normal font, 6 in the
-- small one. Then the gap after a row, a heading's height (text, rule, gap).
local CHAR_W, SMALL_W, LINE, SMALL_H, GAP, HEAD = 6, 4, 8, 6, 2, 10
M.CHAR_W, M.SMALL_W = CHAR_W, SMALL_W

local STATUS = {pending = "...", reading = "reading...", none = "Not found", error = "Can't read"}

local coords = require("gps.core.fix").text
local names = require("gps.core.logname").lines

-- Where things sit on the page (before scrolling). Headings at 0 and 20,
-- telemetry at 10, the button or the logs from 30 (every 26 px: about 2.5
-- on a 64 px screen), the note.
local LOGS = 2 * HEAD + LINE + GAP
local LOG_H = 3 * LINE
local ROW = LOG_H + GAP
local function row_y(i)
  if i == 1 then return HEAD end
  return LOGS + (i - 2) * ROW
end

-- Height of row i: a log's three lines, or one for telemetry and the button.
local function row_h(s, i)
  if i == 1 or i > #s.entries then return LINE end
  return LOG_H
end

-- The lines of row i, and how many of them are in the small font. Logs are
-- numbered from 1, newest first. A name that isn't EdgeTX's carries on to
-- the second line.
local function row_lines(s, i, chars)
  if i > #s.entries then
    if s.effect then return {"Listing logs..."} end
    return {string.format("Show %d last logs", s.ctx.cfg.max_files)}
  end
  local e = s.entries[i]
  if e.kind == "telemetry" then
    if s.telem then return {coords(s.telem)} end
    return {"no GPS fix"}
  end
  local first, second = names(e.name)
  first = string.format("%d. %s", i - 1, first)
  if second == "" then -- @mutant wrap_name: second == "" => second == nil
    second = string.sub(first, chars + 1)
    first = string.sub(first, 1, chars)
  end
  local line = STATUS[e.status]
  if e.status == "found" then line = coords(e.fix) end
  return {first, " " .. second, line}, 2 -- @mutant small_name: line}, 2 => line}, 0
end

-- Scrolled to the highest place a heading or row starts that still shows
-- the selected row whole: as much as fits above it stays on screen.
local function offset(s, h)
  local need = row_y(s.sel) + row_h(s, s.sel) - h
  if need <= 0 then return 0 end
  if need <= LOGS then return math.ceil(need / HEAD) * HEAD end
  return LOGS + math.ceil((need - LOGS) / ROW) * ROW
end

function M.ops(s)
  local w, h = s.ctx.w, s.ctx.h
  local chars, small_chars = math.floor(w / CHAR_W), math.floor(w / SMALL_W)
  local out = {}
  local function text(y, str, inv, small)
    local n = chars
    if small then n = small_chars end
    if #str > n then str = string.sub(str, 1, n) end
    out[#out + 1] = {op = "text", x = 0, y = y, s = str, inv = inv, small = small}
  end
  local off = offset(s, h)
  local function heading(y, str)
    y = y - off
    if y >= 0 and y + LINE + 1 <= h then
      text(y, str, false, false)
      out[#out + 1] = {op = "fill", x = 0, y = y + LINE, w = w, h = 1}
    end
  end
  -- Only rows on screen get their text made (row false: the note). The row
  -- after the last whole one shows the lines of it that fit: there's more.
  local function block(y, bh, i)
    y = y - off
    if y < 0 or y + SMALL_H > h then return end
    local sel, lines, small = i == s.sel, false, 0
    if i then lines, small = row_lines(s, i, small_chars) else lines = {s.log_note[1], " " .. s.log_note[2]} end
    if sel then out[#out + 1] = {op = "fill", x = 0, y = y, w = w, h = bh} end
    for k = 1, #lines do
      local sm, th = k <= (small or 0), LINE
      if sm then th = SMALL_H end
      if y + th > h then return end
      text(y, lines[k], sel, sm)
      y = y + LINE
    end
  end
  heading(0, "Telemetry")
  local rows = app.rows(s)
  for i = 1, rows do
    if i == 2 then heading(2 * HEAD, "Logs") end
    block(row_y(i), row_h(s, i), i)
  end
  if rows == 1 then heading(2 * HEAD, "Logs") end
  if s.log_note then
    local y = LOGS
    if rows > 1 then y = row_y(rows + 1) end
    block(y, 2 * LINE, false)
  end
  return out
end

return M
