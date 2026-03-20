# main.janet — entry point, window lifetime, main loop
#
# SDL2 → raylib migration notes:
#   * (sdl/init) was SDL_Init(SDL_INIT_VIDEO) — now a no-op in the C module.
#   * (sdl/create-window) now calls InitWindow internally via raylib.
#   * (sdl/create-renderer) returns a dummy handle; no separate GPU context.
#   * (sdl/clear) calls BeginDrawing; (sdl/present) calls EndDrawing.
#   * Frame pacing: raylib's SetTargetFPS(60) replaces the manual SDL_Delay loop.
#   * Fonts: LoadFontEx replaces TTF_OpenFont; no sdl2_ttf dependency.

(import janet_raylib :as rl)
(import ./engine)
(import ./ui)

# ── Font search paths ─────────────────────────────────────────
# Try several OS-specific locations; fall back to raylib's built-in font.

(def FONT-CANDIDATES
  ["/usr/local/share/fonts/dejavu/DejaVuSansMono.ttf"    # FreeBSD
   "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"  # Debian/Ubuntu
   "/usr/share/fonts/TTF/DejaVuSansMono.ttf"              # Arch Linux
   "/System/Library/Fonts/Menlo.ttc"                      # macOS fallback
   ""])                                                    # empty → raylib default

(defn- find-font []
  (var found "")
  (each path FONT-CANDIDATES
    (when (and (= found "") (not= path ""))
      (when (os/stat path)
        (set found path))))
  found)

# ── Main ──────────────────────────────────────────────────────

(defn main [& _args]
  # 1. Open window (InitWindow is called inside create-window in janet_raylib.c)
  (rl/init)
  (def win (rl/create-window "Gold Box Engine — Dragonlance"
                             ui/WIN-W ui/WIN-H))
  (def ren (rl/create-renderer win))

  # 2. Load font
  (def font-path (find-font))
  (def font
    (if (= font-path "")
      (do
        (eprint "Warning: DejaVu font not found — using raylib default font.")
        (rl/open-font "" 16))    # empty path triggers fallback in janet_raylib.c
      (rl/open-font font-path 16)))

  # 3. Build initial game state
  (def state (engine/make-state))

  # 4. Main loop
  (while (state :running)
    # Render
    (ui/render-frame ren font state)
    # Process events (populates ring-buffer inside rl/present; drained here)
    (engine/process-events! state))

  # 5. Cleanup
  (rl/close-font font)
  (rl/destroy-renderer ren)
  (rl/destroy-window win)
  (rl/quit))
