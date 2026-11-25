-- Find the newest valid GPS fix in an EdgeTX log CSV by reading it backwards
-- in fixed-size chunks, so each call does a bounded amount of work.
--
--   local cols = M.header(first_bytes)        -- column positions, or nil, why
--   local st = M.start(file_size, chunk)
--   while not st.done do
--     local offset, len = M.request(st)       -- caller reads these bytes
--     st = M.feed(st, bytes, cols)
--   end
--   st.found  -- {lat, lon, date, time}, or false
--
-- The newest line may still be being written; anything after the file's
-- last newline is ignored.
local fix = require("gps.core.fix")

local M = {}

-- Plain split that keeps empty fields.
function M.split(s, sep)
  local out, start = {}, 1
  while true do
    local i = string.find(s, sep, start, true)
    if not i then
      out[#out + 1] = string.sub(s, start)
      return out
    end
    out[#out + 1] = string.sub(s, start, i - 1)
    start = i + 1
  end
end

local function trim_cr(s)
  if string.sub(s, -1) == "\r" then return string.sub(s, 1, -2) end
  return s
end

-- The first `upto` fields of a CSV line. Quoted fields may hold commas and
-- doubled quotes (EdgeTX quotes the flight mode, e.g. "AIR!"). Stops early,
-- so a long row costs only as much as the columns asked for.
function M.fields(line, upto)
  local out, pos, len = {}, 1, #line
  for n = 1, upto do
    if string.sub(line, pos, pos) == '"' then
      local buf, i = "", pos + 1 -- a string: the radio's Lua has no table library
      while true do
        local q = string.find(line, '"', i, true)
        if not q then -- unterminated: take the rest
          buf = buf .. string.sub(line, i)
          pos = len + 1
          break
        end
        buf = buf .. string.sub(line, i, q - 1)
        if string.sub(line, q + 1, q + 1) == '"' then -- @mutant csv_escaped_quote: == '"' then => == "x" then
          buf = buf .. '"'
          i = q + 2
        else
          pos = q + 1
          break
        end
      end
      out[n] = buf
      pos = (string.find(line, ",", pos, true) or len + 1) + 1
    else
      local c = string.find(line, ",", pos, true)
      if not c then c = len + 1 end
      out[n] = string.sub(line, pos, c - 1)
      pos = c + 1
    end
    if pos > len + 1 then return out end
  end
  return out
end

-- Column positions from the header line. Needs the whole first line.
function M.header(text)
  local nl = string.find(text, "\n", 1, true)
  if not nl then return nil, "no_header" end
  local line = trim_cr(string.sub(text, 1, nl - 1))
  local names = M.fields(line, #line + 1)
  local cols = {gps = false, date = false, time = false, last = 0}
  for i = 1, #names do
    if names[i] == "GPS" then cols.gps = i
    elseif names[i] == "Date" then cols.date = i
    elseif names[i] == "Time" then cols.time = i end
  end
  if not cols.gps then return nil, "no_gps" end
  cols.last = math.max(cols.gps, cols.date or 0, cols.time or 0)
  return cols
end

-- A data row's fix, or nil. EdgeTX writes the GPS column as "lat lon" and
-- leaves it empty while there is no fix.
function M.parse_row(line, cols)
  local f = M.fields(trim_cr(line), cols.last)
  local g = f[cols.gps]
  if not g then return nil end
  local a, b = string.match(g, "^%s*(%S+)%s+(%S+)%s*$")
  local lat, lon = tonumber(a), tonumber(b)
  if not fix.valid(lat, lon) then return nil end
  return {
    lat = lat, lon = lon,
    date = cols.date and f[cols.date] or false,
    time = cols.time and f[cols.time] or false,
  }
end

function M.start(size, chunk)
  return {size = size, chunk = chunk, next_end = size, carry = "", tail = true,
          found = false, done = size <= 0, err = false}
end

-- The byte range to read next: [offset, offset + len).
function M.request(st)
  local off = st.next_end - st.chunk
  if off < 0 then off = 0 end
  return off, st.next_end - off
end

-- carry: the start of the oldest line seen so far, whose beginning lies in
-- the part not read yet. tail: carry is still the file's unterminated end.
function M.feed(st, text, cols)
  local off, len = M.request(st)
  local nxt = {size = st.size, chunk = st.chunk, next_end = off, carry = "", tail = false,
               found = false, done = false, err = false}
  if #text ~= len then
    nxt.done, nxt.err = true, "short_read"
    return nxt
  end
  local segs = M.split(text .. st.carry, "\n")
  local k = #segs
  local first, last = 2, k
  if off == 0 then first = 1 end
  if st.tail then last = k - 1 end -- @mutant drop_partial_tail: last = k - 1 => last = k
  for i = last, first, -1 do -- @mutant newest_first: for i = last, first, -1 => for i = first, last
    local f = M.parse_row(segs[i], cols)
    if f then
      nxt.found, nxt.done = f, true
      return nxt
    end
  end
  if off == 0 then
    nxt.done = true
  else
    nxt.carry = segs[1]
    nxt.tail = st.tail and k == 1
  end
  return nxt
end

return M
