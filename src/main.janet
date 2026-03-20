# main.janet — entry point, window lifetime, main loop

(import janet_raylib :as rl)
(import ./engine)
(import ./ui)

(def FONT-CANDIDATES
  ["/usr/local/share/fonts/dejavu/DejaVuSansMono.ttf"    # FreeBSD
   "/usr/share/fonts/truetype/dejavu/DejaVuSansMono.ttf"  # Debian/Ubuntu
   "/usr/share/fonts/TTF/DejaVuSansMono.ttf"              # Arch Linux
   "/System/Library/Fonts/Menlo.ttc"                      # macOS fallback
   ""])                                                    # raylib built-in

(defn- find-font []
  (var found "")
  (each path FONT-CANDIDATES
    (when (and (= found "") (not= path ""))
      (when (os/stat path)
        (set found path))))
  found)

(defn main [& _args]
  (rl/open-window "Gold Box Engine — Dragonlance" ui/WIN-W ui/WIN-H)

  (def font-path (find-font))
  (def font
    (if (= font-path "")
      (do (eprint "Warning: DejaVu font not found — using built-in font.")
          (rl/open-font "" 16))
      (rl/open-font font-path 16)))

  (def state (engine/make-state))

  (while (state :running)
    (ui/render-frame font state)
    (engine/process-events! state))

  (rl/close-font font)
  (rl/close-window))
