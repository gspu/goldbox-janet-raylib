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

(defn- find-tex-dir []
  "Locate the textures/ folder relative to the working directory."
  (var found "textures")
  (each candidate ["textures" "../textures" (string (os/cwd) "/textures")]
    (when (and (= found "textures") (os/stat candidate))
      (set found candidate)))
  found)

(defn- load-textures []
  "Auto-discover and load every .png in the textures/ folder.
   Returns a table mapping basename (no extension) -> texture handle."
  (def dir (find-tex-dir))
  (def t @{})
  (each entry (os/dir dir)
    (when (string/has-suffix? ".png" entry)
      (def name (string/slice entry 0 (- (length entry) 4)))
      (def path (string dir "/" entry))
      (def tex (rl/load-texture path))
      (if tex
        (put t name tex)
        (eprint (string "Warning: failed to load texture: " path)))))
  (eprint (string "Loaded " (length t) " textures from " dir))
  t)

(defn- unload-textures [textures]
  (loop [[_ tex] :pairs textures]
    (rl/unload-texture tex)))

(defn main [& _args]
  (rl/open-window "Gold Box Engine — Dragonlance" ui/WIN-W ui/WIN-H)

  (def font-path (find-font))
  (def font
    (if (= font-path "")
      (do (eprint "Warning: DejaVu font not found — using built-in font.")
          (rl/open-font "" 16))
      (rl/open-font font-path 16)))

  (def textures (load-textures))
  (def state (engine/make-state))

  (while (state :running)
    (ui/render-frame font state textures)
    (engine/process-events! state))

  (unload-textures textures)
  (rl/close-font font)
  (rl/close-window))
