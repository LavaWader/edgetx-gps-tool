LUA ?= lua5.4
LUAMIN ?= luamin
LUA52 := $(shell command -v lua5.2 2>/dev/null)

.PHONY: all check lint test dist e2e mutate clean

# `make`: build the radio file and run every check against it.
all: check

check: lint test e2e

lint:
	$(LUA) tools/lint.lua src

test:
	$(LUA) tools/test.lua
ifneq ($(LUA52),)
	$(LUA52) tools/test.lua
endif

# dist/SCRIPTS/ goes onto the SD card's SCRIPTS/: bundled into build/, then
# each file minified, keeping its first line (a comment saying what it is and
# where it's from; luamin drops comments). luamin reads stdin: `luamin -f`
# hangs on recent Node.
dist:
	rm -rf build dist
	$(LUA) tools/bundle.lua src build
	cd build && for f in $$(find SCRIPTS -name '*.lua'); do \
	  mkdir -p ../dist/$$(dirname $$f) && { head -n 1 $$f && $(LUAMIN) -c < $$f; } > ../dist/$$f || exit 1; \
	done

e2e: dist
	$(LUA) tools/test.lua --e2e

# Slow: re-runs the suites once per "-- @mutant" marker.
mutate:
	LUA=$(LUA) $(LUA) tools/mutate.lua

clean:
	rm -rf build dist
