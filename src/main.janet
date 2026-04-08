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
  "Locate textures/: ./textures (build layout) or ../textures (dev layout from src/)."
  (var found nil)
  (each candidate ["./textures" "textures" "../textures" (string (os/cwd) "/textures")]
    (when (and (not found) (os/stat candidate))
      (set found candidate)))
  (or found "textures"))

(defn- load-dir-into! [t base-dir prefix]
  "Load all .png files from base-dir into table t, keyed as prefix/basename."
  (when (os/stat base-dir)
    (each entry (os/dir base-dir)
      (when (string/has-suffix? ".png" entry)
        (def name (string prefix (string/slice entry 0 (- (length entry) 4))))
        (def path (string base-dir "/" entry))
        (def tex (rl/load-texture path))
        (if tex
          (put t name tex)
          (eprint (string "Warning: failed to load: " path)))))))

(defn- load-textures []
  "Load all .png textures from textures/ and textures/enemies/.
   Root textures are keyed by basename; enemy sprites as enemies/<name>."
  (def dir (find-tex-dir))
  (def t @{})
  (load-dir-into! t dir "")
  (load-dir-into! t (string dir "/enemies") "enemies/")
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
