# Makefile — goldbox-janet, raylib backend
# BSD make and GNU make compatible.
# Run all targets from the repo root (goldbox-janet/).

JANET   ?= janet
JPM     ?= jpm
CC      ?= cc

# ── Janet ─────────────────────────────────────────────────────
JANET_CFLAGS  != pkg-config --cflags janet 2>/dev/null \
                 || echo -I/usr/local/include
JANET_LDFLAGS != pkg-config --libs   janet 2>/dev/null \
                 || echo -L/usr/local/lib -ljanet

# ── Raylib ────────────────────────────────────────────────────
RL_CFLAGS  != pkg-config --cflags raylib 2>/dev/null \
              || echo -I/usr/local/include
RL_LDFLAGS != pkg-config --libs   raylib 2>/dev/null \
              || echo -L/usr/local/lib -lraylib

SYS_LDFLAGS ?= -lm -lpthread -ldl

# ── Compile & link flags ──────────────────────────────────────
CFLAGS  = -O2 -fPIC -Wall -Wextra \
          $(JANET_CFLAGS) $(RL_CFLAGS)
LDFLAGS = -shared \
          $(JANET_LDFLAGS) \
          $(RL_LDFLAGS) \
          $(SYS_LDFLAGS)

MODULE = janet_raylib.so
SRC    = janet_raylib.c

# ── Targets ───────────────────────────────────────────────────
.PHONY: all native clean run exe symbols debug show-entry show-symbols

all: native

# ── Development: .so + janet interpreter ──────────────────────

native: src/$(MODULE)

src/$(MODULE): $(SRC) Makefile
	$(CC) $(CFLAGS) -o src/$(MODULE) $(SRC) $(LDFLAGS)

run: native
	cd src && JANET_PATH=. $(JANET) main.janet

# ── Native executable via jpm ─────────────────────────────────
#
# Produces:  build/goldbox          (executable)
#            build/janet_raylib.so  (native module, loaded at startup)
#            build/maps/            (map data)
#
# jpm looks for native modules in build/ during source evaluation.
# We pre-build both the .so (for module loading) and the .a (for
# linking) into build/ before jpm runs so all DAG steps succeed in
# a single pass.
#
# No _janet_mod_config is exported — without it Janet skips the
# config-bits check entirely, which is safe for same-version builds.

exe: native
	@command -v $(JPM) > /dev/null 2>&1 \
	    || (echo "Error: jpm not found. Install with: pkg install janet"; exit 1)
	mkdir -p build
	# Pre-build .so into build/ — jpm finds it for module evaluation.
	# Compiled normally so it exports _janet_init for dynamic loading.
	$(CC) $(CFLAGS) -o build/$(MODULE) $(SRC) $(LDFLAGS)
	# Pre-build .a into build/ — jpm links this into the executable.
	# MUST be compiled with -DJANET_ENTRY_NAME=janet_module_entry_janet_raylib
	# so the archive exports the mangled symbol that goldbox.c calls.
	$(CC) $(CFLAGS) -DJANET_ENTRY_NAME=janet_module_entry_janet_raylib 	    -c -o build/janet_raylib.static.o $(SRC)
	ar rcs build/janet_raylib.a build/janet_raylib.static.o
	# Remove dev .so from src/ so jpm doesn't find a conflicting copy
	rm -f src/$(MODULE)
	# Single jpm build pass — all prerequisites are in build/
	$(JPM) build
	# Restore dev .so so make run still works
	$(MAKE) native
	# Copy map data and strip build artefacts
	cp -r maps build/maps
	rm -f build/*.o build/*.c build/*.meta.janet build/*.a
	# Patch RPATH so the binary finds janet_raylib.so next to itself
	@if command -v patchelf > /dev/null 2>&1; then \
	    patchelf --set-rpath '$$ORIGIN' build/goldbox \
	    && echo "RPATH set to \$$ORIGIN"; \
	else \
	    echo "Note: patchelf not found. Run with: cd build && env LD_LIBRARY_PATH=. ./goldbox"; \
	fi
	@echo ""
	@echo "Build contents:"
	@ls -lh build/
	@echo ""
	@echo "Run:    cd build && ./goldbox"
	@echo "Deploy: copy the entire build/ directory."

# ── Clean ─────────────────────────────────────────────────────

clean:
	rm -f src/$(MODULE)
	rm -rf build/ .jpm-bootstrap/

# ── Diagnostics ───────────────────────────────────────────────

symbols: src/$(MODULE)
	@nm -g src/$(MODULE) | grep -q _janet_init \
	    && echo "OK: _janet_init exported" \
	    || (echo "ERROR: _janet_init not found"; exit 1)

debug: native
	$(JANET) src/debug.janet 2>&1

show-entry:
	$(CC) $(CFLAGS) -E $(SRC) | grep -A3 "rl_entry\|_janet_init\|module_entry\|asm"

show-symbols: src/$(MODULE)
	nm -g src/$(MODULE) | grep " T "

# ── Installation notes ────────────────────────────────────────
# FreeBSD:      pkg install janet jpm raylib dejavu patchelf
# Debian/Ubuntu: sudo apt install janet libraylib-dev fonts-dejavu patchelf
