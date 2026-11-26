# Groundwork

Applied guideline: `groundwork` @ `8da6afb` (Saga is not a layer anymore).

## Runtime envelope

- **Radio:** EdgeTX on black-and-white radios: Lua 5.2, about 192 KB of heap shared with the firmware (running it out also drops the radio link), one `run()` call per frame. Measured on a RadioMaster Boxer, EdgeTX 2.8.4.
- **Stand-in:** desktop Lua 5.4 runs every test; `make test` also runs the unit tests on `lua5.2` when it's installed. Neither is the radio's build, so the budgets run on 5.4 only.
- **Budgets:** instructions per call, heap peak (garbage included) and memory to compile each shipped file: the `MAX_*` constants in `e2e/smoke_test.lua`, measured on the minified build. Set below what failed on the Boxer: the original QR script peaked at 93 KB and crashed it; a file needing 36 KB to compile loaded, one needing 90 KB didn't. The fake loads stripped bytecode as EdgeTX's `loadScript` does; the first run after copying compiles from source and may need more.
- **Bounded growth:** the folder listing holds at most 2 × `max_files` names, and a log line longer than `line_max` stops that log's search (both in `src/tool/data/config.lua`).
- **Doesn't bind:** SD card space (nothing is written).

## Forced by the envelope (not domain boundaries)

- On-demand parts, listed in `tools/bundle.lua`: `ui` is always loaded; `logs` and `listing` load when first required and are freed when `app.needs_logs`/`app.needs_listing` say so. A part has several files when one would be too big to compile.
- `tool/core/reading.lua` is split from `app.lua` only so the I/O results ship in the `logs` part. Core requires log code inside functions to keep it out of the main file.
- The list keeps only file names; `gps/core/logname.lua` makes a row's title when it's drawn.
- QR codes were dropped: generating one ran the Boxer's heap out.

## Choices where the guideline is silent

- **Components:** `gps` (core, infra), `tool` (core, data, infra, glue). No saga: the tool only reads.
- **Lint:** `tools/lint.lua` over `luac5.4 -l` listings. No suppression syntax.
  - Core and data use only an allowlist of pure globals; no `tostring`, which formats numbers differently on 5.2 and 5.4.
  - Banned: globals the radio lacks (`table`, `_G`) in shipped files; global assignment, 5.3+ operators, `<const>`/`<close>`, `goto` (luamin can't parse it), non-literal `require`.
  - The comment above a function is one sentence of at most `COMMENT_MAX` characters, in every layer (without suppressions there's no budget to go over). A file's first comment block is its header, and infra's `idempotent:`/`fails:`/`undo:` lines don't count.
- **Duplicates:** the lint fails on two shipped functions of at least `COPY_MIN` instructions with the same opcodes. luac drops local names, so a renamed copy compiles alike; Lua's clone detectors (jscpd, PMD CPD) only find exact copies. A copy inside a larger function isn't caught.
- **Formatting:** lua-language-server's formatter (EmmyLuaCodeStyle), the one editors run; `.editorconfig` sets it up.
- **Type tier:** none; Lua has no static types.
- **Tests** sit beside the code in their layer (`*_test.lua`), so the lint covers them.
- **UI state:** `app.update(state, msg)`; I/O requests are data in `state.effect`, and glue performs at most one per `run()`.
- **Own code instead of a library:**
  - `tools/test.lua` (runner and property checks) and `tools/bundle.lua`: one file each, no LuaRocks, runs wherever `lua5.2`/`lua5.4` does.
  - `tools/mutate.lua`: no mutation tool exists for Lua.
  - `gps/core/csv.lua`: EdgeTX's subset only (no commas or quotes inside fields); a CSV library wouldn't fit the heap.

## Deviations

- `tools/format.lua` formats until the file stops changing, not once: EmmyLuaCodeStyle lines up trailing comments before re-indenting, so one pass can leave work for the next.
- `gps/core/logfiles.lua` `M.add` changes its accumulator in place, so a listing is folded name by name from `dir()`. The accumulator is fresh per listing, and only `gps/infra/logfs.lua` holds it.
- `e2e/` and `tools/` sit outside layer directories: test and build tooling, not app source.

## Known gaps

- **Logs need EdgeTX 2.9+** (`dir()`, `fstat()`); older firmware gets a note, and telemetry still works.
- **The fake isn't checked against a real radio** (`e2e/fake_edgetx.lua`): file access, drawing, keys, `getValue` after the link drops.
- **Mutation testing is markers only** (`-- @mutant`, `tools/mutate.lua`): no generated mutants yet.
- **No doc checks yet:** references, values and length budgets in docs and comments are unchecked.
- **Shapes aren't checked:** Lua has no types. The fix shape is built only by `fix.new`, but nothing stops a new `{ lat = ..., lon = ... }` written inline.
