-- EdgeTX tool entry point (SCRIPTS/TOOLS). Wiring only: every decision is in
-- tool/core/app.lua; this file feeds it keys, telemetry and I/O results.
local cfg = require("tool.data.config")
local app = require("tool.core.app")
local view = require("tool.core.view")
local radio = require("tool.infra.radio")
local telemetry = require("gps.infra.telemetry")

-- In the bundle, tools/bundle.lua provides bundle_unload(part) to free an
-- on-demand code part. Unbundled (desktop tests) there is nothing to free.
local unload = bundle_unload or function() end

local state

-- One I/O call per effect kind; the result goes straight back to the core.
-- The log reader is required here, not above: it's in an on-demand part.
local perform = {
  list = function(e)
    local names, err, ver = require("gps.infra.logfs").list(e.dir)
    return {kind = "listed", names = names, err = err, ver = ver}
  end,
  open = function(e)
    local size, head = require("gps.infra.logfs").open(e.path, e.head)
    return {kind = "opened", size = size, head = head}
  end,
  read = function(e)
    return {kind = "chunk", text = require("gps.infra.logfs").read(e.path, e.offset, e.len)}
  end,
}

local function init()
  state = app.init(cfg, LCD_W, LCD_H)
end

local function run(event)
  if state.effect then state = app.update(state, perform[state.effect.kind](state.effect)) end
  state = app.update(state, {kind = "tick", key = radio.key(event), telem = telemetry.read(cfg.gps_sensor)})
  if not app.needs_logs(state) then unload("logs") end
  radio.draw(view.ops(state))
  -- Lua shares the radio's heap: collect this call's garbage now, so it
  -- never piles up (it took the radio down once).
  collectgarbage()
  if state.quit then return 1 end
  return 0
end

return {init = init, run = run}
