# Groundwork

Applied guideline: `groundwork` @ `0ad2b84` (Guide: when to not add layer).

## Choices where the guideline is silent

- **Target:** Lua 5.2 on EdgeTX black-and-white radios. Tests run on desktop Lua 5.4, and `make test` also runs them on `lua5.2` when it's installed.
- **Scope:** a list of positions (telemetry, then SD card logs) shown as text. QR code generation was removed: on a RadioMaster Boxer (EdgeTX 2.8.4) it ran the shared heap out and took the radio down, ELRS link included.
- **Components:** `gps` (core, infra), `tool` (core, data, infra, glue). No saga layer: the tool only reads, one resource at a time.
- **Import/purity check:** `tools/lint.lua` reads `luac5.4 -l` bytecode listings.
  - Core and data may use only an allowlist of pure globals; `tostring` is left out because it formats numbers differently on 5.2 and 5.4.
  - Globals the radio's Lua doesn't have (`table`, `_G`, seen missing on the Boxer) are banned in every shipped file.
  - Global assignment is banned everywhere, as are 5.3+ operators, `<const>`/`<close>`, `goto` (luamin can't parse it) and `require` with a non-literal name.
  - There's no suppression syntax.
- **Type tier:** none. Lua has no static types.
- **Tests:** they sit beside the code in their layer (`*_test.lua`), so the lint covers them too.
- **UI state:** `tool/core/app.lua` is `update(state, msg)`. I/O requests are data in `state.effect`, and the glue performs at most one per `run()` call, then feeds the result back.
- **Budgets, checked by `e2e/smoke_test.lua` on the built files** (desktop Lua 5.4, so ratios matter more than exact numbers):
  - Instructions per `run()` call: 10k.
  - Heap peak, garbage included, sampled inside every call: 60 KB. The fake loads code stripped of debug info, as EdgeTX's `loadScript` does by default (it compiles a `.luac`); that about halves code memory. The first run after copying the files compiles from source and may need more. The original QR script peaks at 93 KB on this measure and crashed the radio; the first version of this tool peaked at 188 KB. The glue runs a full garbage collection at the end of every `run()`.
  - Memory to compile each shipped file: 30 KB. The original script, which compiled on the Boxer, measures 36 KB; the one-file tool measured 90 KB and didn't.
- **Mutation testing:** `-- @mutant id: from => to` markers on core lines, run by `tools/mutate.lua` (`make mutate`).
- **Deployment:** `tools/bundle.lua` builds `SCRIPTS/TOOLS/GPStool.lua` plus part files beside it in `SCRIPTS/TOOLS/GPStool/`, and `make` minifies them with luamin into `dist/`. Test-only modules aren't reachable from the entry point, so they don't ship.
  - The parts are listed in `tools/bundle.lua`: `ui` (the list, always loaded), `logs` (reading logs: file access, CSV, backward scan) and `listing` (keeping the newest names while the folder is read). A part has several files when one would be too big to compile.
  - Nothing on the SD card is touched, and no log code is loaded, until *Show 10 last logs* is pressed.
  - The list keeps only file names; `gps/core/logname.lua` makes a log's two title lines when it's drawn, for the rows on screen only.
  - The folder listing is read `list_batch` names per call: `gps/infra/logfs.lua` keeps the `dir()` iterator between calls, and only the newest `max_files` names (2 × that at most, while reading) are ever held.
  - A part's file is loaded with `loadScript` when one of its modules is first required. The glue frees `logs` whenever `app.needs_logs(state)` says it isn't needed.
  - Core modules require log code inside functions, not at load time, so the bundle can keep it out of the main file.

## Deviations

- `gps/core/logfiles.lua` `M.add` changes its accumulator in place, so a folder listing can be folded name by name from `dir()` without holding it whole. The accumulator is fresh per listing and only `gps/infra/logfs.lua` holds it.
- `e2e/` and `tools/` sit outside layer directories. They shell out, read files and load the bundle, so they're test and build tooling, not app source.

## Known gaps

- **Logs need EdgeTX 2.9 or newer:** `dir()` and `fstat()` came in 2.9 (missing on the Boxer's 2.8.4). On older firmware the list says "Logs need EdgeTX 2.9+" and the installed version; telemetry still works.
- **The fake isn't checked against a real radio** (`e2e/fake_edgetx.lua`): `dir`, `fstat`, `io.read`/`io.seek`, drawing, key events, and `getValue` for GPS after the link drops.
- **Instruction limit per call is unconfirmed;** 10k is a target.
- **Radio memory budget is unknown.** The Boxer showed "Free mem 56b" after an out-of-memory error, a reading after the failure rather than a budget.
- **Log order:** comes from the dates in the file names, which come from the radio clock (a sample log showed `2000-01-01`). When the clock reads 2005 or earlier at start (`getDateTime()`; it resets to 2000 when its battery goes flat), the list warns about it; logs already dated 2000 aren't flagged.
- **CSV fields are split at every comma:** EdgeTX's quoted text fields (the flight mode) hold no commas in the logs seen so far. One that did would shift the columns after it, and that row's GPS field wouldn't parse.
- **Property tests:** no shrinking; the failing input is printed as generated.
