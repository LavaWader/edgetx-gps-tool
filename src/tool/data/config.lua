-- Settings that ship with the tool.
return {
  gps_sensor = "GPS",     -- telemetry sensor name, as in the model's Telemetry page
  log_dir = "/LOGS",
  max_files = 10,         -- newest log files listed, as the button says (each costs memory)
  list_batch = 25,        -- folder entries read per call
  header_max = 2048,      -- bytes read to find the CSV header line
  chunk = 256,            -- bytes read per call when searching a log backwards
}
