LUA ?= lua5.4
LUAMIN ?= luamin
JSCPD ?= jscpd
LUA52 := $(shell command -v lua5.2 2>/dev/null)
# The language server's binary itself: it runs a script given to it. (Arch's
# /usr/bin/lua-language-server is a wrapper that always starts the server.)
LUALS ?= $(firstword $(wildcard /usr/lib/lua-language-server/bin/lua-language-server) lua-language-server)
LUA_FILES = $(shell find src e2e tools -name '*.lua' | sort)

.PHONY: all check format format-check lint dupes test dist e2e mutate clean

# `make`: format the code, build the radio file and run every check against it.
all: format check

# The editor's formatter (lua-language-server's), set by .editorconfig.
format:
	$(LUALS) tools/format.lua $(CURDIR) $(LUA_FILES)

# CI: fail on code that isn't formatted, rather than format it.
format-check:
	$(LUALS) tools/format.lua --check $(CURDIR) $(LUA_FILES)

check: lint dupes test e2e

lint:
	$(LUA) tools/lint.lua src

# Copied code in shipped files; the settings are in .jscpd.json.
dupes:
	$(JSCPD)

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
