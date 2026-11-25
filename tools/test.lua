-- Minimal test runner with seeded property checks.
-- Kept small on purpose: every other check in this repo is only as honest as
-- this file, so read it before trusting a green run.
--
--   lua tools/test.lua [--root DIR] [--e2e] [--seed N]
--     default: runs DIR/src/**/*_test.lua (unit tests, no I/O)
--     --e2e:   runs e2e/*_test.lua (loads DIR/dist/)
--
-- A test file returns a list of {name, function(t) ... end}. `t` provides:
--   t.ok(cond, msg), t.eq(actual, expected, msg)  -- deep equality
--   t.forall(n, gen, check)  -- n cases from gen(rng); reports the failing input
--   t.rng                    -- seeded per test: same seed, same cases
--   t.root                   -- the --root directory

local root, e2e = ".", false
local seed = tonumber(os.getenv("SEED") or "") or 20261124
local i = 1
while i <= #arg do
  if arg[i] == "--root" then
    root = arg[i + 1]; i = i + 1
  elseif arg[i] == "--e2e" then
    e2e = true
  elseif arg[i] == "--seed" then
    seed = tonumber(arg[i + 1]); i = i + 1
  else
    error("unknown argument " .. arg[i])
  end
  i = i + 1
end

-- EdgeTX runs Lua 5.2, which has bit32. Newer interpreters get a shim.
if not bit32 then
  bit32 = load([[
    local M = {}
    function M.bxor(a, b) return a ~ b end
    function M.band(a, b) return a & b end
    function M.bor(a, b) return a | b end
    function M.rshift(a, n) return a >> n end
    function M.lshift(a, n) return (a << n) & 0xFFFFFFFF end
    return M
  ]])()
end

package.path = root .. "/src/?.lua;" .. root .. "/e2e/?.lua;" .. package.path

-- MINSTD Lehmer generator: plain arithmetic, so it behaves the same on 5.2 and 5.4.
local function new_rng(s)
  s = s % 2147483647
  if s <= 0 then s = s + 2147483646 end
  local r = {}
  function r.next()
    s = (s * 48271) % 2147483647; return s
  end

  function r.int(lo, hi) return lo + r.next() % (hi - lo + 1) end

  function r.float(lo, hi) return lo + (hi - lo) * (r.next() - 1) / 2147483645 end

  function r.bool() return r.next() % 2 == 0 end

  function r.pick(list) return list[r.int(1, #list)] end

  return r
end

local function show(v, depth)
  depth = depth or 0
  if type(v) == "string" then return string.format("%q", v) end
  if type(v) ~= "table" then return tostring(v) end
  if depth > 2 then return "{...}" end
  local parts, n = {}, 0
  for k, x in pairs(v) do
    n = n + 1
    if n > 16 then
      parts[#parts + 1] = "..."; break
    end
    parts[#parts + 1] = tostring(k) .. "=" .. show(x, depth + 1)
  end
  return "{" .. table.concat(parts, ", ") .. "}"
end

local function deep_eq(a, b)
  if a == b then return true end
  if type(a) ~= "table" or type(b) ~= "table" then return false end
  for k, v in pairs(a) do if not deep_eq(v, b[k]) then return false end end
  for k in pairs(b) do if a[k] == nil then return false end end
  return true
end

local function make_t(name)
  local h = 0
  for k = 1, #name do h = (h * 31 + name:byte(k)) % 2147483647 end
  local t = { root = root, rng = new_rng(seed + h) }
  function t.ok(cond, msg)
    if not cond then error(msg or "expected a true value", 2) end
  end

  function t.eq(actual, expected, msg)
    if not deep_eq(actual, expected) then
      error((msg and (msg .. ": ") or "") .. "expected " .. show(expected) .. ", got " .. show(actual), 2)
    end
  end

  function t.forall(n, gen, check)
    for k = 1, n do
      local case = gen(t.rng)
      local ok, err = pcall(check, case)
      if not ok then
        error(string.format("case %d/%d failed: %s\n      input: %s", k, n, tostring(err), show(case)), 0)
      end
    end
  end

  return t
end

local dir = e2e and "e2e" or (root .. "/src")
local p = io.popen('find "' .. dir .. '" -name "*_test.lua" | sort')
local files = {}
for line in p:lines() do files[#files + 1] = line end
p:close()

local pass, fail = 0, 0
if #files == 0 then
  print("FAIL no test files found under " .. dir); fail = 1
end
for _, f in ipairs(files) do
  local short = (f:gsub("^.*/src/", ""))
  local ok, tests = pcall(dofile, f)
  if not ok then
    fail = fail + 1
    print("FAIL " .. short .. " (load): " .. tostring(tests))
  else
    for _, tc in ipairs(tests) do
      local name = short .. " :: " .. tc[1]
      local ok2, err = pcall(tc[2], make_t(name))
      if ok2 then
        pass = pass + 1
      else
        fail = fail + 1; print("FAIL " .. name .. "\n    " .. tostring(err))
      end
    end
  end
end
print(string.format("%s: %d passed, %d failed (seed %d)", e2e and "e2e" or "unit", pass, fail, seed))
os.exit(fail == 0)
