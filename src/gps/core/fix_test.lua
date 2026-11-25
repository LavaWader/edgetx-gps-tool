local fix = require("gps.core.fix")

return {
  {"valid: in range, not 0,0", function(t)
    t.ok(fix.valid(54.687156, 25.279651), "Vilnius")
    t.ok(fix.valid(0, 25.5), "on the equator")
    t.ok(fix.valid(54.5, 0), "on the prime meridian")
    t.ok(fix.valid(90, 180) and fix.valid(-90, -180), "edges")
    t.ok(not fix.valid(0, 0), "0,0 is what receivers send without a fix")
    t.ok(not fix.valid(90.000001, 1), "lat too big")
    t.ok(not fix.valid(1, -180.000001), "lon too small")
    t.ok(not fix.valid(0 / 0, 1), "NaN")
    t.ok(not fix.valid(1 / 0, 1), "infinity")
    t.ok(not fix.valid("54.1", 25), "strings are not numbers")
    t.ok(not fix.valid(nil, 25), "missing")
  end},

  {"from_telemetry takes getValue's table, rejects everything else", function(t)
    t.eq(fix.from_telemetry({lat = 1.5, lon = 2.5}), {lat = 1.5, lon = 2.5})
    t.eq(fix.from_telemetry(0), nil)
    t.eq(fix.from_telemetry({lat = 0, lon = 0}), nil)
    t.eq(fix.from_telemetry(nil), nil)
  end},

  {"text round-trips to 5 decimals and fits 20 characters", function(t)
    t.forall(300, function(rng) return {lat = rng.float(-90, 90), lon = rng.float(-180, 180)} end,
      function(c)
        local s = fix.text(c)
        local lat, lon = string.match(s, "^(%-?%d+%.%d%d%d%d%d),(%-?%d+%.%d%d%d%d%d)$")
        t.ok(lat, "format: " .. s)
        t.ok(#s <= 20, "length: " .. s)
        t.ok(math.abs(tonumber(lat) - c.lat) <= 0.000005 and math.abs(tonumber(lon) - c.lon) <= 0.000005, "value")
      end)
    t.eq(fix.text({lat = -90, lon = -180}), "-90.00000,-180.00000", "the longest")
  end},
}
