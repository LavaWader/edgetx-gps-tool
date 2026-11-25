-- A fake EdgeTX environment for running the built tool headless.
-- It follows the EdgeTX Lua API as documented, but it is NOT checked against
-- a real radio (see GROUNDWORK.md, known gaps): what passes here can still
-- fail on the radio if the real API behaves differently.
local M = {}

local KEYS = {enter = 101, exit = 102, next = 103, prev = 104}

-- path: the tool, .../SCRIPTS/TOOLS/<name>.lua; its SCRIPTS folder is served
-- as /SCRIPTS. opts: gps = {lat, lon} or nil, logs_dir = local folder served
-- as /LOGS, w, h = screen size.
function M.load(path, opts)
  local scripts = assert(path:match("^(.*)/TOOLS/[^/]+$"), "not in a SCRIPTS/TOOLS folder: " .. path)
  local W, H = opts.w or 128, opts.h or 64
  local fb, texts = {}, {}
  local real_io = io
  local env = setmetatable({}, {__index = _G})
  local radio = {gps = opts.gps, fb = fb, texts = texts, w = W, h = H, loads = {}, sd_calls = 0}
  -- Each part runs in its own environment table, held weakly: while the
  -- part's functions are alive, so is its table.
  local alive = setmetatable({}, {__mode = "k"})
  -- Work done inside the fake API is native code on a radio: don't count it.
  local native = 0
  local function api(f)
    return function(...)
      native = native + 1
      local ok, a, b = pcall(f, ...)
      native = native - 1
      if not ok then error(a, 0) end
      return a, b
    end
  end

  -- Pixels are XORed: the strictest guess at how the radio combines
  -- overlapping drawing, so overlaps show up as wrong pixels here.
  local function fill(x, y, w, h)
    for py = y, y + h - 1 do
      for px = x, x + w - 1 do
        if px >= 0 and px < W and py >= 0 and py < H then
          fb[py * W + px + 1] = not fb[py * W + px + 1]
        end
      end
    end
  end
  env.lcd = {
    clear = api(function()
      for i = 1, W * H do fb[i] = false end
      for i = #texts, 1, -1 do texts[i] = nil end
    end),
    drawText = api(function(x, y, s, flags) texts[#texts + 1] = {x = x, y = y, s = s, flags = flags or 0} end),
    drawFilledRectangle = api(fill),
    drawRectangle = function() end,
  }
  env.LCD_W, env.LCD_H, env.INVERS, env.SMLSIZE = W, H, 1, 0x200
  env.EVT_VIRTUAL_ENTER, env.EVT_VIRTUAL_EXIT = KEYS.enter, KEYS.exit
  env.EVT_VIRTUAL_NEXT, env.EVT_VIRTUAL_PREV = KEYS.next, KEYS.prev
  env.getFieldInfo = function(name)
    if name == "GPS" then return {id = 42} end
    return nil
  end
  env.getValue = function(id)
    if id == 42 and radio.gps then return {lat = radio.gps.lat, lon = radio.gps.lon} end
    return 0
  end

  local local_path
  function local_path(p)
    if opts.logs_dir and string.sub(p, 1, 6) == "/LOGS/" then return opts.logs_dir .. "/" .. string.sub(p, 7) end
    return nil
  end
  -- opts.firmware = "2.8.4": no dir() and no fstat(), as on that version.
  env.getVersion = function() return opts.firmware or "2.10.0" end
  -- dir() is native on the radio: the folder is read here, before the heap
  -- baseline, and the iterator's own work isn't counted either.
  local listing = {}
  if opts.logs_dir then
    local h = real_io.popen('ls -1 "' .. opts.logs_dir .. '"')
    for line in h:lines() do listing[#listing + 1] = line end
    h:close()
  end
  env.dir = api(function(p)
    radio.sd_calls = radio.sd_calls + 1
    if p ~= "/LOGS" or not opts.logs_dir then error("no such folder") end
    local i = 0
    return api(function() i = i + 1; return listing[i] end)
  end)
  env.fstat = api(function(p)
    radio.sd_calls = radio.sd_calls + 1
    local lp = local_path(p)
    local f = lp and real_io.open(lp, "rb")
    if not f then return nil end
    local size = f:seek("end")
    f:close()
    return {size = size}
  end)
  if opts.firmware and opts.firmware < "2.9" then env.dir, env.fstat = nil, nil end
  -- EdgeTX's io: io.read(file, length), io.seek(file, offset).
  env.io = {
    open = function(p)
      radio.sd_calls = radio.sd_calls + 1
      local lp = local_path(p)
      return lp and real_io.open(lp, "rb")
    end,
    read = function(f, n) return f:read(n) or "" end,
    seek = function(f, off) f:seek("set", off); return 0 end,
    close = function(f) f:close() end,
  }

  -- Compiling is native on the radio. Loads are recorded in order.
  env.loadScript = api(function(p)
    if string.sub(p, 1, 9) ~= "/SCRIPTS/" then return nil, "not under /SCRIPTS: " .. p end
    radio.loads[#radio.loads + 1] = p
    local penv = setmetatable({}, {__index = env})
    alive[penv] = p
    return loadfile(scripts .. "/" .. string.sub(p, 10), "t", penv)
  end)

  for i = 1, W * H do fb[i] = false end -- the fake's screen isn't the tool's memory
  collectgarbage("collect")
  local base_kb = collectgarbage("count")
  radio.base_kb = base_kb
  local tool = assert(loadfile(path, "t", env))()
  radio.tool = tool
  radio.max_instructions, radio.max_kb, radio.max_peak_kb = 0, 0, 0

  -- Part files in memory now, sorted (call after a full collection).
  function radio.parts()
    local list = {}
    for _, p in pairs(alive) do list[#list + 1] = p end
    table.sort(list)
    return list
  end

  -- Calls f the way the radio's tool loop calls the script, counting its own
  -- VM instructions and sampling the heap every 20 of them for the peak
  -- (garbage included: on a black-and-white radio Lua shares the system heap,
  -- and running it out took the radio down). Heap is relative to before the
  -- tool was loaded.
  local function measured(f, label, ...)
    local count = 0
    debug.sethook(function()
      if native == 0 then count = count + 1 end
      if count % 20 == 0 then
        local kb = collectgarbage("count") - base_kb
        if kb > radio.max_peak_kb then radio.max_peak_kb, radio.peak_at = kb, label end
      end
    end, "", 1)
    local ret = f(...)
    debug.sethook()
    local kb = collectgarbage("count") - base_kb
    if kb > radio.max_peak_kb then radio.max_peak_kb, radio.peak_at = kb, label end
    radio.last_instructions = count
    if count > radio.max_instructions then radio.max_instructions, radio.max_at = count, label end
    collectgarbage("collect")
    kb = collectgarbage("count") - base_kb
    if kb > radio.max_kb then radio.max_kb = kb end
    return ret
  end

  function radio.init() return measured(tool.init, "init") end
  function radio.run(key) return measured(tool.run, key or "tick", KEYS[key] or 0) end

  -- Whether some text on screen reads s, ignoring the spaces that pad a
  -- selected row into a bar.
  function radio.has_text(s)
    for _, t in ipairs(texts) do if t.s:match("^%s*(.-)%s*$") == s then return true end end
    return false
  end

  -- The flags some text was drawn with, or nil.
  radio.SMLSIZE = env.SMLSIZE
  function radio.text_flags(s)
    for _, t in ipairs(texts) do if t.s:match("^%s*(.-)%s*$") == s then return t.flags end end
    return nil
  end

  function radio.idle_until(s, limit)
    for _ = 1, limit do
      if radio.has_text(s) then return true end
      radio.run(nil)
    end
    return radio.has_text(s)
  end

  return radio
end

return M
