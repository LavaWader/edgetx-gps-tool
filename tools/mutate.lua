-- Mutation check: proves the tests catch the bugs we expect them to.
--
-- A marker at the end of a source line names one deliberate bug:
--     if x < n then  -- @mutant my_id: x < n => x <= n
-- FROM must occur exactly once in the code before the marker. For each marker
-- this copies src/ to a temp dir, applies FROM => TO on that line, rebuilds
-- dist/ there with `make dist` (so the e2e tests see minified files, as
-- shipped) and runs unit + e2e tests there. A mutant that still passes
-- ("survives") is a rule no test checks.
--
--   lua tools/mutate.lua [ID ...]     (default: every marker)

local LUA = os.getenv("LUA") or "lua5.4"
local only = {}
for _, a in ipairs(arg) do only[a] = true end
local filter = next(only) ~= nil

local function sh(cmd) return os.execute(cmd) == true end
local function quiet(cmd) return sh(cmd .. " >/dev/null 2>&1") end
local function read(path)
  local f = assert(io.open(path, "rb")); local s = f:read("*a"); f:close(); return s
end
local function write(path, s)
  local f = assert(io.open(path, "wb")); f:write(s); f:close()
end

local mutants, ids = {}, {}
local p = io.popen("grep -rl --include='*.lua' '@mutant' src | grep -v '_test.lua$' | sort")
for file in p:lines() do
  local lineno = 0
  for line in (read(file) .. "\n"):gmatch("([^\n]*)\n") do
    lineno = lineno + 1
    local code, id, from, to = line:match("^(.-)%-%-%s*@mutant%s+([%w_%-]+):%s*(.-)%s+=>%s+(.-)%s*$")
    if code then
      local a = code:find(from, 1, true)
      assert(a and not code:find(from, a + 1, true),
        file .. ":" .. lineno .. ": '" .. from .. "' must occur exactly once before the marker")
      assert(not ids[id], "duplicate mutant id " .. id)
      ids[id] = true
      if not filter or only[id] then
        mutants[#mutants + 1] = { id = id, file = file, line = lineno, from = from, to = to }
      end
    end
  end
end
p:close()
if #mutants == 0 then
  print("mutate: no markers selected"); os.exit(false)
end

local function suite(dir)
  return quiet("make -C " .. dir .. " dist LUA=" .. LUA)
      and quiet("timeout 300 " .. LUA .. " tools/test.lua --root " .. dir)
      and quiet("timeout 300 " .. LUA .. " tools/test.lua --e2e --root " .. dir)
end

local function workdir()
  local h = io.popen("mktemp -d")
  local d = h:read("*l")
  h:close()
  assert(quiet("cp -r src tools e2e Makefile " .. d .. "/"))
  return d
end

local base = workdir()
if not suite(base) then
  print("mutate: the unmutated suite fails; fix that first"); os.exit(false)
end
quiet("rm -rf " .. base)

local survived = {}
for k, m in ipairs(mutants) do
  local d = workdir()
  local path = d .. "/" .. m.file
  local out, n = {}, 0
  for line in (read(path) .. "\n"):gmatch("([^\n]*)\n") do
    n = n + 1
    if n == m.line then
      local a = line:find(m.from, 1, true)
      line = line:sub(1, a - 1) .. m.to .. line:sub(a + #m.from)
    end
    out[#out + 1] = line
  end
  write(path, table.concat(out, "\n"))
  local killed = not suite(d)
  quiet("rm -rf " .. d)
  print(string.format("[%d/%d] %-26s %s  (%s:%d)", k, #mutants, m.id, killed and "killed" or "SURVIVED", m.file, m.line))
  if not killed then survived[#survived + 1] = m.id end
end

print(string.format("mutate: %d killed, %d survived", #mutants - #survived, #survived))
os.exit(#survived == 0)
