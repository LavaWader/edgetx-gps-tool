-- Settings that ship with the tool.
return {
  gps_sensor = "GPS",     -- telemetry sensor name, as in the model's Telemetry page
  log_dir = "/LOGS",
  max_files = 60,         -- newest log files listed
  header_max = 2048,      -- bytes read to find the CSV header line
  chunk = 512,            -- bytes read per call when searching a log backwards
}
