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
#            build/maps/            (map data files)
#
# Install jpm (FreeBSD): ships with janet since 1.17 — try: which jpm
# Install jpm (Linux):   https://github.com/janet-lang/jpm

exe:
	@command -v $(JPM) > /dev/null 2>&1 \
	    || (echo "Error: jpm not found. Install with: pkg install janet"; exit 1)
	# Build a bootstrap .so in a temp dir so jpm can load the module
	# during Janet source evaluation without interfering with jpm's own
	# build pipeline inside build/ (which creates .a, .static.o etc.)
	mkdir -p .jpm-bootstrap
	$(CC) $(CFLAGS) -o .jpm-bootstrap/$(MODULE) $(SRC) $(LDFLAGS)
	# Remove dev .so from src/ so jpm doesn't find a stale copy there
	rm -f src/$(MODULE)
	# JANET_PATH=.jpm-bootstrap lets jpm evaluate main.janet and find
	# the module; jpm's own build/ pipeline runs completely uninterrupted
	JANET_PATH=.jpm-bootstrap $(JPM) build
	rm -rf .jpm-bootstrap
	# Rebuild dev .so so make run still works
	$(MAKE) native
	cp -r maps build/maps
	rm -f build/*.o build/*.c build/*.meta.janet build/*.a
	@echo ""
	@echo "Build contents:"
	@ls -lh build/
	@echo ""
	@echo "Run:    cd build && ./goldbox"
	@echo "Deploy: copy the entire build/ directory."

# ── Clean ─────────────────────────────────────────────────────
# Removes everything: dev .so and the entire build/ directory.

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
# FreeBSD:      pkg install janet raylib dejavu
# Debian/Ubuntu: sudo apt install janet libraylib-dev fonts-dejavu
