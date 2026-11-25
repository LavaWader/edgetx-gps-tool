# EdgeTX GPS position tool

An EdgeTX tool (SYS → Tools) for black-and-white radios: lists your model's GPS position from live telemetry and from SD card logs, as text.

**Status:** passes its headless tests. Log rows need EdgeTX 2.9 or newer (`dir()` and `fstat()` came in 2.9); on older firmware the list says so, and telemetry still works.

- **Install:** run `make` (builds and checks). Copy `dist/SCRIPTS/TOOLS/` into `SCRIPTS/TOOLS/` on the SD card: `GPStool.lua` and the `GPStool/` folder beside it, which holds the parts the tool loads as needed.
- **Use:**
  - The screen has two headings. *Telemetry* shows the live position. *Logs* has a *Show 10 last logs* button: the SD card isn't read until you press it.
  - The button lists the ten newest logs (`max_files` in `src/tool/data/config.lua`) (numbered from 1), each as its date and time to the second and its model name (small font), then its last position.
  - NEXT/PREV move (stopping at the ends), ENTER presses the button, EXIT closes the tool.
  - When there are no log rows, a note says why (for example *Logs need EdgeTX 2.9+*).
- **Logs:** add an *SD Logs* special function (MDL → SPECIAL FUNCTIONS), and set the radio's date and time so the newest log is listed first.
- **Develop:** `make` runs the lint, unit tests and end-to-end tests against the minified files. It needs `lua5.4`, `luac5.4` and `luamin`. `make mutate` checks that the tests catch the bugs marked in the code.
- **Radio check:** `tools/probe/PROBE.lua` is a separate tool that shows which Lua APIs a radio's firmware has.
- **Layout:** `src/<component>/<layer>/` (components `gps`, `tool`), `e2e/` for tests against the built files, `tools/` for the build and check scripts.
- **Architecture:** design choices, budgets and known gaps are in [GROUNDWORK.md](GROUNDWORK.md).
