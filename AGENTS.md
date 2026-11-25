# Agent instructions

- Read `GROUNDWORK.md` first.
- Run every check with `make` (same as `make check`). Run `make mutate` after changing core logic or its tests.
- Rules no check enforces:
  - Glue stays wiring. `run()` performs the pending effect, sends one tick to `app.update`, frees the parts `app.parts` says aren't needed, and draws `view.ops`. Any decision goes in a core transition.
  - Require log modules inside functions in `tool/core`, never at the top: a top-level require pulls that code into the main file, which then may not compile on the radio (`make` checks the size).
  - New logic goes in a `core/` module, with property tests over generated inputs.
  - Agent-written tests are checked by mutation: give each new rule a `-- @mutant id: from => to` marker and make sure `make mutate` kills it.
- A decision that changes or deviates from the guideline gets a bullet in `GROUNDWORK.md`.
