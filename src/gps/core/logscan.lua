-- Find the newest valid GPS fix in an EdgeTX log CSV by reading it backwards
-- in fixed-size chunks, so each call does a bounded amount of work.
--
--   local cols = csv.header(first_bytes)      -- gps/core/csv.lua: columns, or nil, why
--   local st = M.start(file_size, chunk, line_max)
--   while not st.done do
--     local offset, len = M.request(st)       -- caller reads these bytes
--     st = M.feed(st, bytes, cols)
--   end
--   st.found  -- {lat, lon}, or false
--
-- The newest line may still be being written; anything after the file's
-- last newline is ignored.
local csv = require("gps.core.csv")

local M = {}


function M.start(size, chunk, line_max)
  return {
    size = size,
    chunk = chunk,
    line_max = line_max,
    next_end = size,
    carry = "",  -- the start of the oldest line read so far: its beginning isn't read yet
    tail = true, -- carry is still the file's unterminated end
    found = false,
    done = size <= 0,
    err = false
  }
end

-- The byte range to read next: [offset, offset + len).
function M.request(st)
  local off = st.next_end - st.chunk
  if off < 0 then off = 0 end
  return off, st.next_end - off
end

-- The state after reading the bytes M.request asked for.
function M.feed(st, text, cols)
  local off, len = M.request(st)
  local nxt = {
    size = st.size,
    chunk = st.chunk,
    line_max = st.line_max,
    next_end = off,
    carry = "",
    tail = false,
    found = false,
    done = false,
    err = false
  }
  if #text ~= len then
    nxt.done, nxt.err = true, "short_read"
    return nxt
  end
  local segs = csv.split(text .. st.carry, "\n")
  local k = #segs
  local first, last = 2, k
  if off == 0 then first = 1 end
  if st.tail then last = k - 1 end -- @mutant drop_partial_tail: last = k - 1 => last = k
  for i = last, first, -1 do       -- @mutant newest_first: for i = last, first, -1 => for i = first, last
    local f = csv.parse_row(segs[i], cols)
    if f then
      nxt.found, nxt.done = f, true
      return nxt
    end
  end
  if off == 0 then
    nxt.done = true
  elseif #segs[1] > st.line_max then -- @mutant line_cap: #segs[1] > st.line_max => false
    nxt.done, nxt.err = true, "line_too_long"
  else
    nxt.carry = segs[1]
    nxt.tail = st.tail and k == 1
  end
  return nxt
end

return M
