# Makefile — goldbox-janet, raylib backend
# BSD make and GNU make compatible.
# Run all targets from the repo root (goldbox-janet/).

JANET   ?= janet
CC      ?= cc

# ── Janet ─────────────────────────────────────────────────────
JANET_CFLAGS  != pkg-config --cflags janet 2>/dev/null \
                 || echo -I/usr/local/include
JANET_LDFLAGS != pkg-config --libs   janet 2>/dev/null \
                 || echo -L/usr/local/lib -ljanet

# ── Raylib ────────────────────────────────────────────────────
# On FreeBSD:  pkg install raylib
# On Linux:    apt install libraylib-dev   (or build from source)
RL_CFLAGS  != pkg-config --cflags raylib 2>/dev/null \
              || echo -I/usr/local/include
RL_LDFLAGS != pkg-config --libs   raylib 2>/dev/null \
              || echo -L/usr/local/lib -lraylib

# raylib on FreeBSD/Linux needs these system libraries
SYS_LDFLAGS ?= -lm -lpthread -ldl

# ── Compile & link flags ──────────────────────────────────────
#
# Plain default symbol visibility — no -fvisibility flag.
# _janet_init is exported along with all other globals; fine for a module.
#
# Intentionally NOT used:
#   --version-script  — lld (FreeBSD default) rejects it when the named
#                        symbol isn't resolved yet at script-parse time.
#   -fvisibility=hidden — older Janet headers define JANET_MODULE_ENTRY
#                        without JANET_API, so _janet_init gets hidden and
#                        Janet reports "could not find the _janet_init symbol".
#
CFLAGS  = -O2 -fPIC -Wall -Wextra \
          $(JANET_CFLAGS) $(RL_CFLAGS)
LDFLAGS = -shared \
          $(JANET_LDFLAGS) \
          $(RL_LDFLAGS) \
          $(SYS_LDFLAGS)

MODULE = janet_raylib.so
SRC    = janet_raylib.c

# ── Targets ───────────────────────────────────────────────────
.PHONY: all native clean run symbols debug

all: native

native: src/$(MODULE)

src/$(MODULE): $(SRC) Makefile
	$(CC) $(CFLAGS) -o src/$(MODULE) $(SRC) $(LDFLAGS)

clean:
	rm -f src/$(MODULE)

run: native
	cd src && $(JANET) main.janet

# Verify _janet_init is exported
symbols: src/$(MODULE)
	@nm -g src/$(MODULE) | grep -q _janet_init \
	    && echo "OK: _janet_init exported" \
	    || (echo "ERROR: _janet_init not found"; exit 1)

debug: native
	$(JANET) src/debug.janet 2>&1

# Show what the preprocessor makes of the entry-point section.
# Run this to diagnose symbol-naming issues: make show-entry
show-entry:
	$(CC) $(CFLAGS) -E janet_raylib.c | grep -A3 "rl_entry\|_janet_init\|module_entry\|asm"

# Dump all exported symbols from the built .so
show-symbols: src/$(MODULE)
	nm -g src/$(MODULE) | grep " T "

# ── Installation notes ────────────────────────────────────────
# FreeBSD:
#   pkg install janet raylib dejavu
#
# Linux (Debian/Ubuntu):
#   sudo apt install janet libraylib-dev fonts-dejavu
#
# The game looks for the font at /usr/local/share/fonts/dejavu/
# (FreeBSD) or /usr/share/fonts/truetype/dejavu/ (Linux Debian).
# janet_raylib.c falls back to the built-in raylib font if the
# file is not found, so the game is still playable without DejaVu.
