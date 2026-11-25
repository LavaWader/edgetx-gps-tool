-- Build the tool as files for the SD card's SCRIPTS folder:
--   lua tools/bundle.lua SRC_DIR OUT_DIR
-- writes OUT_DIR/SCRIPTS/TOOLS/GPStool.lua (the tool) and the part files
-- below, OUT_DIR/SCRIPTS/TOOLS/GPStool/<file>.lua (beside the tool, as other
-- EdgeTX tools keep their files).
--
-- Each module becomes a function; a local `require` runs it on first use.
-- A file's modules are only loaded (loadScript) when one of them is first
-- required, and bundle_unload(part) drops all of a part's files again: the
-- radio never has to compile, or keep, the whole tool at once. A part has
-- several files when one would take too much memory to compile.
local SRC, OUT = arg[1], arg[2]
assert(SRC and OUT, "usage: bundle.lua SRC_DIR OUT_DIR")

local ENTRY = "tool.glue.main"
local NAME = "GPStool"           -- file and folder name on the SD card
local TITLE = "GPS tool"         -- shown in SYS -> Tools
local PART_DIR = "/SCRIPTS/TOOLS/" .. NAME .. "/"
-- Part files and their roots; a file also takes every module its roots reach
-- that no other file has.
-- "ui" is never unloaded: it's split off only so no file is too big to compile.
local PARTS = {
  {name = "ui", files = {
    {file = "ui", roots = {"tool.core.app", "gps.core.fix"}},
    {file = "uiview", roots = {"tool.core.view"}},
  }},
  {name = "logs", files = {
    {file = "logs", roots = {"tool.core.reading", "gps.infra.logfs"}},
    {file = "csv", roots = {"gps.core.csv"}},
    {file = "logscan", roots = {"gps.core.logscan"}},
  }},
  -- Sorting the folder listing: needed only inside the call that handles it.
  {name = "listing", files = {
    {file = "logfiles", roots = {"gps.core.logfiles"}},
  }},
}

local function read(name)
  local path = SRC .. "/" .. name:gsub("%.", "/") .. ".lua"
  local f = assert(io.open(path, "rb"), "missing module " .. name .. " (" .. path .. ")")
  local text = f:read("*a")
  f:close()
  return text
end

local owner = {} -- module -> "main" or part name
for _, p in ipairs(PARTS) do
  for _, f in ipairs(p.files) do
    for _, r in ipairs(f.roots) do owner[r] = f.file end
  end
end

-- Modules reachable from `roots` without passing through modules owned elsewhere.
local function collect(roots, me)
  local order, seen = {}, {}
  local function visit(name)
    if seen[name] then return end
    seen[name] = true
    if owner[name] and owner[name] ~= me then return end
    local text = read(name)
    for dep in text:gmatch('require%s*%(%s*"([%w_%.]+)"%s*%)') do visit(dep) end
    owner[name] = me
    order[#order + 1] = {name = name, text = text}
  end
  for _, r in ipairs(roots) do visit(r) end
  return order
end

local function emit(lines, mods)
  for _, m in ipairs(mods) do
    lines[#lines + 1] = '__mods["' .. m.name .. '"] = function()'
    lines[#lines + 1] = m.text
    lines[#lines + 1] = "end"
  end
end

local function write(path, lines)
  os.execute('mkdir -p "' .. path:match("^(.*)/") .. '"')
  local f = assert(io.open(path, "wb"))
  f:write(table.concat(lines, "\n"), "\n")
  f:close()
end

local main = collect({ENTRY}, "main")
local files, map, units = {}, {}, {}
for _, p in ipairs(PARTS) do
  for _, f in ipairs(p.files) do
    local mods = collect(f.roots, f.file)
    files[#files + 1] = {name = f.file, mods = mods}
    units[#units + 1] = f.file .. ' = "' .. p.name .. '"'
    for _, m in ipairs(mods) do map[#map + 1] = '["' .. m.name .. '"] = "' .. f.file .. '"' end
  end
end

local out = {
  "-- GPS tool for EdgeTX, https://github.com/LavaWader/edgetx-gps-tool (generated: edit src/, not this file)",
  'local toolName = "TNS|' .. TITLE .. '|TNE"',
  "local __mods, __done, __loaded = {}, {}, {}",
  "local __file = {" .. table.concat(map, ", ") .. "}",
  "local __part = {" .. table.concat(units, ", ") .. "}",
  "local require",
  "function require(name)",
  "  local m = __done[name]",
  "  if m == nil then",
  "    local f = __file[name]",
  "    if f and not __loaded[f] then",
  "      collectgarbage()",
  '      local chunk, err = loadScript("' .. PART_DIR .. '" .. f .. ".lua")',
  "      if not chunk then error(err) end",
  "      chunk(__mods, require)",
  "      __loaded[f] = true",
  "    end",
  "    m = __mods[name](); __done[name] = m",
  "  end",
  "  return m",
  "end",
  "local function bundle_unload(p)",
  "  local any = false",
  "  for f in pairs(__loaded) do",
  "    if __part[f] == p then any = true; __loaded[f] = nil end",
  "  end",
  "  if not any then return end",
  "  for name, f in pairs(__file) do",
  "    if __part[f] == p then __mods[name] = nil; __done[name] = nil end",
  "  end",
  "  collectgarbage()",
  "end",
}
emit(out, main)
out[#out + 1] = 'return require("' .. ENTRY .. '")'
write(OUT .. "/SCRIPTS/TOOLS/" .. NAME .. ".lua", out)
print(string.format("bundle: %d modules -> %s/SCRIPTS/TOOLS/%s.lua", #main, OUT, NAME))

for _, p in ipairs(files) do
  local lines = {
    "-- File '" .. p.name .. "' of the GPS tool, loaded by SCRIPTS/TOOLS/" .. NAME .. ".lua. Generated; edit src/.",
    "local __mods, require = ...",
  }
  emit(lines, p.mods)
  local path = OUT .. PART_DIR .. p.name .. ".lua"
  write(path, lines)
  print(string.format("bundle: %d modules -> %s", #p.mods, path))
end
