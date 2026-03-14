# debug.janet — step-by-step subsystem diagnostic
#
# Run with:  janet src/debug.janet 2>&1
# or:        make debug
#
# The last step printed before a crash tells you exactly which
# subsystem failed.  Each step tests a progressively larger slice
# of the engine.
#
# SDL2 → raylib migration:
#   * Steps 1-6 are pure-Janet and unchanged.
#   * Steps 7-18 previously tested SDL2 calls; they now test the
#     equivalent raylib calls via janet_raylib.so.

(print "=== Gold Box Engine — raylib diagnostic ===")
(print)

# ── Step 1: RNG ───────────────────────────────────────────────
(print "[ 1] Loading rng...")
(import ./rng)
(print "[ 2] d6  = " (rng/d6))
(print "[ 3] d20 = " (rng/d20))
(print "[ 4] rand-int 100 = " (rng/rand-int 100))
(print "[ 5] rand-bool = " (rng/rand-bool))

# ── Step 2: World ─────────────────────────────────────────────
(print "[ 6] Loading world...")
(import ./world)
(def w (world/make-world))
(print "[ 7] World created. Level=" (w :level) " Player=" (w :player))
(print "[ 8] tile-at (2,2) = " (world/tile-at (w :tiles) 2 2))
(print "[ 9] passable? (2,2) = " (world/passable? (w :tiles) 2 2))
(world/reveal-fog! w)
(print "[10] Fog revealed. fog[0]=" ((w :fog) 0))

# ── Step 3: Party ─────────────────────────────────────────────
(print "[11] Loading party...")
(import ./party)
(def p (party/make-party))
(print "[12] Party created. Members: " (map |($ :name) p))
(print "[13] Tanis HP=" ((p 0) :hp) " THAC0=" ((p 0) :thac0))

# ── Step 4: Combat ────────────────────────────────────────────
(print "[14] Loading combat...")
(import ./combat)
(def monsters [(world/make-monster :baaz-draconian)])
(def cs (combat/make-combat p monsters))
(print "[15] Combat state created. Phase=" (cs :phase))
(print "[16] Living monsters: " (length (combat/living-monsters cs)))
(print "[17] Hero turn? " (combat/hero-turn? cs))

# ── Step 5: raylib native module ──────────────────────────────
(print "[18] Importing janet_raylib native module...")
(import ./janet_raylib :as rl)
(print "[19] janet_raylib imported. SC_UP=" rl/SC_UP " SC_RETURN=" rl/SC_RETURN)

# ── Step 6: Window & renderer ─────────────────────────────────
(print "[20] Calling rl/init...")
(rl/init)
(print "[21] rl/init OK")

(print "[22] Creating window (headless — window will open briefly)...")
(def win (rl/create-window "Debug Test" 320 240))
(print "[23] Window handle = " win)

(def ren (rl/create-renderer win))
(print "[24] Renderer handle = " ren)

# ── Step 7: Font loading ──────────────────────────────────────
(def FONT-PATHS
  ["/usr/local/share/fonts/dejavu/DejaVuSansMono.ttf"
   "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"
   "/usr/share/fonts/TTF/DejaVuSansMono.ttf"
   ""])

(print "[25] Searching for DejaVu font...")
(var font-path "")
(each path FONT-PATHS
  (when (and (= font-path "") (not= path ""))
    (when (os/stat path)
      (set font-path path))))
(print "[26] Font path: " (if (= font-path "") "(using raylib built-in)" font-path))

(def font (rl/open-font font-path 16))
(print "[27] Font loaded: " font)

# ── Step 8: Draw calls ────────────────────────────────────────
(print "[28] Testing draw calls...")

(rl/set-color ren 20 20 20 255)
(rl/clear ren)
(print "[29] rl/clear OK")

(rl/set-color ren 200 170 50 255)
(rl/fill-rect ren 10 10 100 50)
(print "[30] rl/fill-rect OK")

(rl/set-color ren 255 255 255 255)
(rl/draw-rect ren 10 10 100 50)
(print "[31] rl/draw-rect OK")

(rl/set-color ren 60 200 200 255)
(rl/draw-line ren 0 0 100 100)
(print "[32] rl/draw-line OK")

(rl/draw-text ren font "Debug OK" 10 70 255 255 255 255)
(print "[33] rl/draw-text OK")

# ── Step 9: Present / ticks ───────────────────────────────────
(print "[34] Calling rl/present...")
(rl/present ren)
(print "[35] rl/present OK. ticks=" (rl/ticks))

# ── Step 10: Event poll (just drain immediately) ──────────────
(print "[36] Testing rl/poll-events...")
(var ev (rl/poll-events))
(var ev-count 0)
(while ev
  (++ ev-count)
  (set ev (rl/poll-events)))
(print "[37] poll-events drained " ev-count " events.")

# ── Teardown ──────────────────────────────────────────────────
(print "[38] Closing font...")
(rl/close-font font)
(print "[39] Destroying renderer...")
(rl/destroy-renderer ren)
(print "[40] Destroying window...")
(rl/destroy-window win)
(print "[41] Calling rl/quit...")
(rl/quit)

(print)
(print "=== All 41 steps passed — raylib backend is functional ===")
