# EdgeTX GPS position tool

An EdgeTX tool (SYS → Tools) for black-and-white radios: lists your model's GPS position from live telemetry and from SD card logs, as text.

**Status:** passes its headless tests. Log rows need EdgeTX 2.9 or newer (`dir()` and `fstat()` came in 2.9); on older firmware the list says so, and telemetry still works.

- **Install:** download `GPStool-<version>.zip` from the [releases](https://github.com/LavaWader/edgetx-gps-tool/releases) and unzip it at the SD card's root. It holds `SCRIPTS/TOOLS/GPStool.lua` and the `GPStool/` folder beside it, with the parts the tool loads as needed. Replace both when updating.
  - From source: run `make` (builds and checks), then copy `dist/SCRIPTS/TOOLS/` into `SCRIPTS/TOOLS/` on the SD card.
- **Release:** push a tag `v*` (e.g. `git tag v1.0.0 && git push origin v1.0.0`). `.github/workflows/build.yml` runs every check, including `make mutate` and the unit tests on Lua 5.2, then publishes the release with the zip. Pushes and pull requests get the same checks, and the zip as a run artifact.
- **Use:**
  - The screen has two headings. *Telemetry* shows the live position. *Logs* has a *Show 10 last logs* button: the SD card isn't read until you press it.
  - The button lists the ten newest logs (`max_files` in `src/tool/data/config.lua`) (numbered from 1), each as its date and time to the second and its model name (small font), then its last position.
  - NEXT/PREV move (stopping at the ends), EXIT closes the tool. ENTER presses the button, or reads the selected row again: a log's file, or telemetry (it shows *reading...* for half a second).
  - When there are no log rows, a note says why (for example *Logs need EdgeTX 2.9+*).
- **Logs:** add an *SD Logs* special function (MDL → SPECIAL FUNCTIONS), and set the radio's date and time so the newest log is listed first.
- **Develop:** `make` runs the lint, unit tests and end-to-end tests against the minified files. It needs `lua5.4`, `luac5.4` and `luamin`. `make mutate` checks that the tests catch the bugs marked in the code.
- **Radio check:** `tools/probe/PROBE.lua` is a separate tool that shows which Lua APIs a radio's firmware has.
- **Layout:** `src/<component>/<layer>/` (components `gps`, `tool`), `e2e/` for tests against the built files, `tools/` for the build and check scripts.
- **Architecture:** design choices, budgets and known gaps are in [GROUNDWORK.md](GROUNDWORK.md).
