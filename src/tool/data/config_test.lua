-- Tests of the shipped settings.
local cfg = require("tool.data.config")

return {
  { "settings are in range", function(t)
    t.ok(cfg.chunk >= 64, "chunk")
    t.ok(cfg.header_max >= 256, "header_max")
    t.ok(cfg.max_files >= 1 and cfg.list_batch >= 1, "max_files, list_batch")
    t.eq(string.sub(cfg.log_dir, 1, 1), "/", "absolute log dir")
  end },
}
