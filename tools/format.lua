-- Format Lua files the way the editor does: with lua-language-server's own
-- formatter (EmmyLuaCodeStyle, the `code_format` module built into it), set
-- up by the repo's .editorconfig as the language server sets it up.
-- Run by the language server's binary, which can run a script instead of
-- serving (`make format` does this):
--
--   lua-language-server tools/format.lua [--check] <root> <file.lua>...
--
-- Rewrites the files that change; with --check, only lists them and fails.
local code_format = require("code_format")

local args = { ... }
local check = args[1] == "--check"
if check then table.remove(args, 1) end
local root = table.remove(args, 1)

local function uri(path) return "file://" .. path end

-- As the language server does: the .editorconfig for the folder it's in
-- (1: created). No editor options: an editor's indent settings would win over
-- .editorconfig, and Neovim sets them from it anyway.
local ok, err = code_format.update_config(1, uri(root), root .. "/.editorconfig")
if not ok then
  io.stderr:write("format: .editorconfig: ", tostring(err), "\n")
  os.exit(2)
end

local changed = 0
for _, path in ipairs(args) do
  local f = assert(io.open(path, "rb"))
  local text = f:read("a")
  f:close()
  -- Again until it settles: one pass can leave work for the next (trailing
  -- comments lined up after the code moved), and a file that's settled is one
  -- the editor's single pass on save leaves alone.
  local out, prev = text, nil
  for _ = 1, 5 do
    if out == prev then break end
    local done, res = code_format.format(uri(root .. "/" .. path), out, {})
    if not done then
      io.stderr:write("format: ", path, ": ", tostring(res), "\n")
      os.exit(2)
    end
    prev, out = out, res
  end
  if out ~= text then
    changed = changed + 1
    if check then
      print("not formatted: " .. path)
    else
      f = assert(io.open(path, "wb"))
      f:write(out)
      f:close()
      print("formatted: " .. path)
    end
  end
end
if check and changed > 0 then os.exit(1) end
