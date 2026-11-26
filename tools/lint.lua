-- Layer, purity and Lua 5.2 compatibility lint for src/. See GROUNDWORK.md.
-- There is deliberately no way to suppress a finding: fix the code or change
-- this file (which is a reviewed diff of its own).
--
--   lua tools/lint.lua [SRC_DIR]     (needs luac5.4 on PATH)

local SRC = arg[1] or "src"
local LUAC = os.getenv("LUAC") or "luac5.4"

local LAYERS = { core = true, data = true, infra = true, glue = true }
-- Which layers a file in each layer may require.
local MAY_REQUIRE = {
  core = { core = true },
  data = { core = true, data = true },
  infra = { core = true, infra = true },
  glue = { core = true, data = true, infra = true, glue = true },
}
-- The only globals core and data may touch: pure standard library.
-- tostring is left out on purpose: it formats numbers differently on 5.2 and 5.4.
local PURE_GLOBALS = {}
for name in ("require math string table bit32 pairs ipairs type error assert select "
  .. "tonumber next pcall setmetatable getmetatable rawget rawset rawequal"):gmatch("%S+") do
  PURE_GLOBALS[name] = true
end
-- Globals EdgeTX's Lua doesn't have, seen on a Boxer with EdgeTX 2.8.4 (no
-- table library, no _G). Banned in every shipped file; tests run on desktop.
local RADIO_MISSING = { table = true, _G = true }
-- Fields core and data may not read (impure, or missing in Lua 5.2).
local BANNED_FIELDS = { random = true, randomseed = true, tointeger = true, ult = true }
-- Opcodes of the 5.3+ integer and bitwise operators; EdgeTX's Lua 5.2 can't parse them.
local BANNED_OPS = {}
for op in ("IDIV IDIVK BAND BANDK BOR BORK BXOR BXORK SHL SHR SHLI SHRI BNOT"):gmatch("%S+") do
  BANNED_OPS[op] = true
end

-- The comment right above a function: one sentence of at most this many
-- characters (the "--" and indentation not counted).
local COMMENT_MAX = 120
-- An infra operation's contract lines, which don't count toward it.
local CONTRACT_KEYS = { idempotent = true, fails = true, undo = true }
-- A shipped function at least this many instructions long has no copy
-- elsewhere, renamed or not: luac drops local names, so a copy compiles alike.
local COPY_MIN = 8

local errors = 0
local function report(file, msg)
  errors = errors + 1
  print(file .. ": " .. msg)
end

local function read(path)
  local f = assert(io.open(path, "rb"))
  local s = f:read("*a")
  f:close()
  return s
end

-- Blank out comments (and strings, unless keep_strings), keeping line breaks.
local function strip(src, keep_strings)
  local out, i, n = {}, 1, #src
  local function blank(s) return (s:gsub("[^\n]", " ")) end
  while i <= n do
    local c = src:sub(i, i)
    local long = src:match("^%-%-%[(=*)%[", i)
    if long then
      local _, e = src:find("]" .. long .. "]", i, true)
      e = e or n
      out[#out + 1] = blank(src:sub(i, e)); i = e + 1
    elseif src:sub(i, i + 1) == "--" then
      local e = src:find("\n", i, true) or (n + 1)
      out[#out + 1] = blank(src:sub(i, e - 1)); i = e
    elseif src:match("^%[=*%[", i) then
      local eq = src:match("^%[(=*)%[", i)
      local _, e = src:find("]" .. eq .. "]", i, true)
      e = e or n
      out[#out + 1] = keep_strings and src:sub(i, e) or blank(src:sub(i, e)); i = e + 1
    elseif c == '"' or c == "'" then
      local j = i + 1
      while j <= n do
        local d = src:sub(j, j)
        if d == "\\" then
          j = j + 2
        elseif d == c then
          break
        else
          j = j + 1
        end
      end
      out[#out + 1] = keep_strings and src:sub(i, j) or (c .. blank(src:sub(i + 1, j - 1)) .. c)
      i = j + 1
    else
      out[#out + 1] = c; i = i + 1
    end
  end
  return table.concat(out)
end

local function defines_function(line)
  return line:match("^%s*local%s+function%f[^%w_]") or line:match("^%s*function%f[^%w_]")
      or line:match("^%s*local%s+[%w_]+%s*=%s*function%s*%(")
      or line:match("^%s*[%w_.:%[%]\"]+%s*=%s*function%s*%(")
end

-- The comment block right above each function, as one line of text. A block
-- starting on the file's first line is the module's header, not a function's.
local function function_comments(src)
  local lines = {}
  for l in (src .. "\n"):gmatch("([^\n]*)\n") do lines[#lines + 1] = l end
  local found = {}
  for i, l in ipairs(lines) do
    local j = i - 1
    while j >= 1 and lines[j]:match("^%s*%-%-") and not lines[j]:match("^%s*%-%-%[=*%[") do j = j - 1 end
    if defines_function(l) and j < i - 1 and j >= 1 then
      local parts = {}
      for k = j + 1, i - 1 do
        local text = lines[k]:match("^%s*%-%-+%s?(.-)%s*$")
        local key = text:match("^(%a+):")
        if not (key and CONTRACT_KEYS[key]) then parts[#parts + 1] = text end
      end
      found[#found + 1] = { line = i, text = table.concat(parts, " ") }
    end
  end
  return found
end

local function sentences(text)
  local t = text:gsub("e%.g%.", "eg"):gsub("i%.e%.", "ie")
  local n = 1
  for _ in t:gmatch("[%.%?!]%s+%S") do n = n + 1 end
  return n
end

local p = io.popen('find "' .. SRC .. '" -type f -name "*.lua" | sort')
local files = {}
for line in p:lines() do files[#files + 1] = line end
p:close()
if #files == 0 then report(SRC, "no Lua files found") end
local graph = {}  -- module -> {file, deps}, requires inside functions included
local shapes = {} -- every shipped function: {file, line, ops = its opcodes}

for _, file in ipairs(files) do
  local rel = file:sub(#SRC + 2)
  local segs = {}
  for seg in rel:gmatch("[^/]+") do segs[#segs + 1] = seg end
  local layer = segs[#segs - 1]

  -- 1. Every file sits directly in exactly one layer directory.
  if not layer or not LAYERS[layer] then
    report(file, "not inside a layer directory (core/data/infra/glue)")
    layer = nil
  end
  for k = 1, #segs - 2 do
    if LAYERS[segs[k]] then report(file, "layer name '" .. segs[k] .. "' used as a component directory") end
  end

  local src = read(file)
  local code = strip(src, true)
  local bare = strip(src, false)

  -- 2. require: literal module names only, pointing the allowed direction.
  local literal = 0
  local deps = {}
  graph[(rel:gsub("%.lua$", ""):gsub("/", "."))] = { file = file, deps = deps }
  for name in code:gmatch('require%s*%(%s*"([%w_%.]+)"%s*%)') do
    literal = literal + 1
    deps[#deps + 1] = name
    local target = SRC .. "/" .. name:gsub("%.", "/") .. ".lua"
    local f = io.open(target, "rb")
    if not f then report(file, "requires missing module " .. name) else f:close() end
    local tsegs = {}
    for seg in name:gmatch("[^%.]+") do tsegs[#tsegs + 1] = seg end
    local tlayer = tsegs[#tsegs - 1]
    if layer and not (tlayer and MAY_REQUIRE[layer][tlayer]) then
      report(file, layer .. " may not require " .. name)
    end
  end
  local mentions = 0
  for _ in bare:gmatch("%f[%w_]require%f[^%w_]") do mentions = mentions + 1 end
  if mentions ~= literal then report(file, "require must be called with a literal module name") end

  -- 3. Syntax EdgeTX's Lua 5.2 (or luamin) can't handle.
  if bare:find("//", 1, true) then report(file, "integer division '//' is Lua 5.3+") end
  if bare:find("<%s*const%s*>") or bare:find("<%s*close%s*>") then report(file, "<const>/<close> are Lua 5.4") end
  if bare:find("%f[%w_]goto%f[^%w_]") then report(file, "goto is not supported by luamin") end

  -- 5. A function's comment says one thing: more means it does more than one.
  for _, c in ipairs(function_comments(src)) do
    local where = "line " .. c.line .. ": "
    if sentences(c.text) > 1 then report(file, where .. "comment above a function has more than one sentence") end
    if #c.text > COMMENT_MAX then
      report(file, where .. "comment above a function is " .. #c.text .. " characters (max " .. COMMENT_MAX .. ")")
    end
  end

  -- 4. Bytecode: global access and banned opcodes.
  local lp = io.popen(LUAC .. ' -p -l -l "' .. file .. '" 2>&1')
  local listing = lp:read("*a")
  lp:close()
  if not listing:find("main <", 1, true) then report(file, "luac failed: " .. listing) end
  if not file:match("_test%.lua$") then
    local fn
    for line in listing:gmatch("[^\n]+") do
      local kind, at = line:match("^(%a+) <[^:]*:(%d+),%d+>")
      if kind then
        fn = nil
        if kind == "function" then
          fn = { file = file, line = at, ops = {} }
          shapes[#shapes + 1] = fn
        end
      elseif fn then
        local op = line:match("^%s*%d+%s+%[%d+%]%s+(%u+)")
        if op then fn.ops[#fn.ops + 1] = op end
      end
    end
  end
  for line in listing:gmatch("[^\n]+") do
    local lineno, op, rest = line:match("^%s*%d+%s+%[(%d+)%]%s+(%u+)%s*(.*)$")
    if op then
      local where = "line " .. lineno .. ": "
      if BANNED_OPS[op] then report(file, where .. "operator " .. op .. " is Lua 5.3+") end
      local global = rest:match('_ENV "([%w_]+)"')
      if op == "SETTABUP" and global then report(file, where .. "assigns global '" .. global .. "'") end
      if op == "GETTABUP" and global and RADIO_MISSING[global] and not file:match("_test%.lua$") then
        report(file, where .. "'" .. global .. "' doesn't exist on the radio")
      end
      if layer == "core" or layer == "data" then
        if op == "GETTABUP" and global and not PURE_GLOBALS[global] then
          report(file, where .. layer .. " may not use global '" .. global .. "'")
        end
        local field = rest:match('; "([%w_]+)"$')
        if op == "GETFIELD" and field and BANNED_FIELDS[field] then
          report(file, where .. layer .. " may not use '" .. field .. "'")
        end
      end
    end
  end
end

-- 7. Copied functions: the same opcodes in the same order, operands ignored.
local first_of = {}
for _, fn in ipairs(shapes) do
  if #fn.ops >= COPY_MIN then
    local key = table.concat(fn.ops, " ")
    local first = first_of[key]
    if first then
      report(fn.file, "line " .. fn.line .. ": a copy of the function at " .. first.file .. ":" .. first.line)
    else
      first_of[key] = fn
    end
  end
end

-- 6. No require cycles, even through requires inside functions.
local state = {} -- module -> "open" while on the path, "done" after
local function visit(name, path)
  if state[name] == "done" or not graph[name] then return end
  if state[name] == "open" then
    local from = 1
    while path[from] ~= name do from = from + 1 end
    local cycle = {}
    for k = from, #path do cycle[#cycle + 1] = path[k] end
    cycle[#cycle + 1] = name
    report(graph[name].file, "require cycle: " .. table.concat(cycle, " -> "))
    return
  end
  state[name] = "open"
  path[#path + 1] = name
  for _, dep in ipairs(graph[name].deps) do visit(dep, path) end
  path[#path] = nil
  state[name] = "done"
end
local names = {}
for name in pairs(graph) do names[#names + 1] = name end
table.sort(names)
for _, name in ipairs(names) do visit(name, {}) end

if errors > 0 then
  print(string.format("lint: %d problem(s)", errors))
  os.exit(false)
end
print(string.format("lint: %d files ok", #files))
