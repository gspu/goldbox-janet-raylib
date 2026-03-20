# ui.janet — Gold Box split-screen renderer
#
# Screen layout (1024×768)
# ┌─────────────────────────────────────────────────────────────┐
# │  Title bar                                      1024×32     │
# ├──────────────────┬───────────────────┬────────────────────  │
# │  3-D view        │  Text / combat    │  Minimap            │
# │  512×420         │  310×420          │  202×420            │
# ├──────────────────┴───────────────────┴────────────────────  │
# │  Party stats bar                                1024×100    │
# ├─────────────────────────────────────────────────────────────│
# │  Message log                                    1024×36     │
# └─────────────────────────────────────────────────────────────┘
#
# The only change from the SDL2 version:
#   (import ./janet_sdl2 :as sdl)  →  (import janet_raylib :as rl)
# All rl/* calls are identical to the old sdl/* calls.

(import janet_raylib :as rl)
(import ./world)
(import ./party)
(import ./combat)

# ── Layout constants ─────────────────────────────────────────

(def WIN-W   1024)
(def WIN-H    768)

(def TITLE-H    32)
(def VIEW-W    512)
(def TEXT-W    310)
(def MINI-W    202)
(def PANEL-H   420)
(def STATS-H   100)
(def MSG-H      36)

(def TITLE-Y     0)
(def PANEL-Y    TITLE-H)
(def VIEW-X      0)
(def TEXT-X    VIEW-W)
(def MINI-X    (+ VIEW-W TEXT-W))
(def STATS-Y   (+ TITLE-H PANEL-H))
(def MSG-Y     (+ STATS-Y STATS-H))

# ── Colour palette ───────────────────────────────────────────

(def COL-BLACK    [  0   0   0 255])
(def COL-DARK     [ 20  20  20 255])
(def COL-STONE    [ 70  60  50 255])
(def COL-FLOOR    [ 40  35  30 255])
(def COL-WALL     [ 90  80  70 255])
(def COL-DOOR     [160 100  30 255])
(def COL-GOLD     [200 170  50 255])
(def COL-WHITE    [255 255 255 255])
(def COL-GRAY     [160 160 160 255])
(def COL-GREEN    [ 60 160  60 255])
(def COL-RED      [200  50  50 255])
(def COL-YELLOW   [220 200  60 255])
(def COL-BLUE     [ 60 100 200 255])
(def COL-CYAN     [ 60 200 200 255])
(def COL-PANEL-BG [ 10  10  20 255])
(def COL-SEP      [ 60  55  50 255])

# ── Draw helpers ─────────────────────────────────────────────

(defn- set-col [ren [r g b a]]
  (rl/set-color ren r g b a))

(defn- fill [ren x y w h col]
  (set-col ren col)
  (rl/fill-rect ren x y w h))

(defn- outline [ren x y w h col]
  (set-col ren col)
  (rl/draw-rect ren x y w h))

(defn- line [ren x1 y1 x2 y2 col]
  (set-col ren col)
  (rl/draw-line ren x1 y1 x2 y2))

(defn- text [ren font str x y col]
  (let [[r g b a] col]
    (rl/draw-text ren font str x y r g b a)))

# ── HP bar helper ────────────────────────────────────────────

(defn- draw-hp-bar [ren x y w h cur mx]
  (fill ren x y w h COL-DARK)
  (when (pos? mx)
    (let [frac (/ cur mx)
          col  (cond (> frac 0.5) COL-GREEN
                     (> frac 0.25) COL-YELLOW
                     COL-RED)]
      (fill ren x y (math/floor (* w frac)) h col)))
  (outline ren x y w h COL-GRAY))

# ── 3-D first-person view — DDA raycaster ────────────────────
#
# Uses the classic Digital Differential Analyzer algorithm:
# for each screen column we cast a ray and step it to exact tile
# grid boundaries (X-boundaries and Y-boundaries separately).
# This guarantees every tile face is hit — no gaps, no pass-through,
# completely solid walls.
#
# Perpendicular wall distance (not Euclidean) is used for wall height
# so there is no fish-eye distortion.

(def FOV 1.0472)       # 60° total field of view in radians (pi/3)
(def VIEW-DEPTH 16)    # max ray distance in tiles

(defn- dda-cast [tiles px py ray-dx ray-dy]
  "DDA ray cast from (px,py) in direction (ray-dx, ray-dy).
   Returns [tile perp-dist side] where side is :x or :y wall face,
   or [nil VIEW-DEPTH :x] if nothing is hit."

  # Current map cell
  (var map-x (math/floor px))
  (var map-y (math/floor py))

  # Length of ray to cross one full cell in each axis
  (def delta-x (if (= ray-dx 0) 1e30 (math/abs (/ 1 ray-dx))))
  (def delta-y (if (= ray-dy 0) 1e30 (math/abs (/ 1 ray-dy))))

  # Step direction and initial side distances
  (var step-x 0)
  (var step-y 0)
  (var side-x 0.0)
  (var side-y 0.0)

  (if (< ray-dx 0)
    (do (set step-x -1)
        (set side-x (* (- px map-x) delta-x)))
    (do (set step-x  1)
        (set side-x (* (- (+ map-x 1) px) delta-x))))

  (if (< ray-dy 0)
    (do (set step-y -1)
        (set side-y (* (- py map-y) delta-y)))
    (do (set step-y  1)
        (set side-y (* (- (+ map-y 1) py) delta-y))))

  # DDA loop — step to nearest grid boundary each iteration
  (var hit false)
  (var side :x)
  (var steps 0)

  (while (and (not hit) (< steps VIEW-DEPTH))
    (if (< side-x side-y)
      (do (set side-x (+ side-x delta-x))
          (set map-x  (+ map-x  step-x))
          (set side    :x))
      (do (set side-y (+ side-y delta-y))
          (set map-y  (+ map-y  step-y))
          (set side    :y)))
    (++ steps)
    # Stop immediately if ray has left the map
    (if (or (< map-x 0) (>= map-x world/MAP-W)
            (< map-y 0) (>= map-y world/MAP-H))
      (set steps VIEW-DEPTH)   # force loop exit
      (let [t (world/tile-at tiles map-x map-y)]
        (when (not= t 0)
          (set hit true)))))

  (if hit
    # Perpendicular distance (Lode's formula) — avoids fish-eye distortion.
    # perp = (map_cell - player_pos + (1 - step) / 2) / ray_dir
    (let [perp (if (= side :x)
                 (/ (+ (- map-x px) (/ (- 1 step-x) 2)) ray-dx)
                 (/ (+ (- map-y py) (/ (- 1 step-y) 2)) ray-dy))
          tile (world/tile-at tiles map-x map-y)]
      [tile (math/abs perp) side])
    [nil VIEW-DEPTH :x]))

# ── Compass rose ─────────────────────────────────────────────

(defn- draw-compass [ren font dir]
  "Draw N/S/E/W compass in the top-right corner of the 3D view."
  (let [cx   (- (+ VIEW-X VIEW-W) 36)   # centre x
        cy   (+ PANEL-Y 36)             # centre y
        r    24                         # outer radius
        # Background circle
        _    (fill ren (- cx r) (- cy r) (* 2 r) (* 2 r) [0 0 0 160])
        _    (outline ren (- cx r) (- cy r) (* 2 r) (* 2 r) COL-SEP)
        # Cardinal directions — highlight the one we face
        dirs {:north ["N"  cx          (- cy r -4)  0 -1]
              :south ["S"  cx          (+ cy r -10) 0  1]
              :east  ["E"  (+ cx r -8) cy           1  0]
              :west  ["W"  (- cx r -2) cy          -1  0]}]
    (eachp [k [lbl tx ty nx ny]] dirs
      (let [active (= k dir)
            col    (if active COL-CYAN COL-GRAY)
            # Tick line from centre toward the cardinal point
            lx2    (+ cx (math/floor (* nx (- r 8))))
            ly2    (+ cy (math/floor (* ny (- r 8))))]
        (line ren cx cy lx2 ly2 (if active COL-CYAN [60 60 60 255]))
        (text ren font lbl tx ty col)))))

(defn draw-3d-view [ren font tiles player]
  # Ceiling and floor background
  (fill ren VIEW-X PANEL-Y VIEW-W (math/floor (/ PANEL-H 2)) COL-STONE)
  (fill ren VIEW-X (+ PANEL-Y (math/floor (/ PANEL-H 2)))
            VIEW-W (math/ceil  (/ PANEL-H 2)) COL-FLOOR)

  (let [# Map Y increases downward (row 0 = top of map).
        # Raycaster steps use map coords directly, so dir-y must match:
        #   north = -Y  (up on map)   → angle = -pi/2  → sin = -1
        #   south = +Y  (down on map) → angle =  pi/2  → sin = +1
        #   east  = +X               → angle =  0
        #   west  = -X               → angle =  pi
        angle (case (player :dir)
                :east   0.0
                :south  1.5708
                :west   3.1416
                :north  4.7124    # = -pi/2, gives dir-y = -1
                0.0)
        cam-len (math/tan (/ FOV 2))
        dir-x   (math/cos angle)
        dir-y   (math/sin angle)
        # Camera plane perpendicular to direction
        plane-x (* (- dir-y) cam-len)
        plane-y (* dir-x     cam-len)
        half    (/ PANEL-H 2)]

    (for screen-x 0 VIEW-W
      (let [cam-x  (- (* 2 (/ screen-x VIEW-W)) 1)
            ray-dx (+ dir-x (* plane-x cam-x))
            ray-dy (+ dir-y (* plane-y cam-x))
            # +0.5 places the ray origin at tile centre, not the corner
            [tile perp-dist side] (dda-cast tiles (+ (player :x) 0.5) (+ (player :y) 0.5) ray-dx ray-dy)]
        (when (and tile (> perp-dist 0))
          (let [wall-h  (math/floor (/ PANEL-H perp-dist))
                top     (math/floor (- half (/ wall-h 2)))
                base    (math/floor (* 255 (max 0 (- 1 (/ perp-dist VIEW-DEPTH)))))
                shade   (if (= side :y) (math/floor (* base 0.7)) base)
                col-shade (cond
                            (= tile 2) [shade (math/floor (* shade 0.6)) 0 255]
                            (= tile 1) [shade shade (math/floor (* shade 0.8)) 255]
                            [(math/floor (* shade 0.8)) shade (math/floor (* shade 0.6)) 255])
                draw-top    (max 0 top)
                draw-bottom (min PANEL-H (+ top wall-h))
                draw-h      (- draw-bottom draw-top)]
            (when (> draw-h 0)
              (set-col ren col-shade)
              (rl/fill-rect ren (+ VIEW-X screen-x) (+ PANEL-Y draw-top) 1 draw-h))))))

  # Compass overlay — drawn after walls so it's always on top
  (draw-compass ren font (player :dir))))

# ── Text / combat panel ───────────────────────────────────────

(defn draw-text-panel [ren font lines title]
  (fill ren TEXT-X PANEL-Y TEXT-W PANEL-H COL-PANEL-BG)
  (outline ren TEXT-X PANEL-Y TEXT-W PANEL-H COL-SEP)
  (text ren font title (+ TEXT-X 8) (+ PANEL-Y 6) COL-GOLD)
  (line ren TEXT-X (+ PANEL-Y 22) (+ TEXT-X TEXT-W) (+ PANEL-Y 22) COL-SEP)
  (var ly (+ PANEL-Y 30))
  (each ln lines
    (text ren font ln (+ TEXT-X 8) ly COL-WHITE)
    (set ly (+ ly 18))))

# ── Minimap ───────────────────────────────────────────────────

(def MINI-CELL 12)    # pixels per map cell

(defn draw-minimap [ren font tiles fog player]
  (fill ren MINI-X PANEL-Y MINI-W PANEL-H COL-DARK)
  (outline ren MINI-X PANEL-Y MINI-W PANEL-H COL-SEP)
  (text ren font "MAP" (+ MINI-X 8) (+ PANEL-Y 6) COL-GOLD)
  (let [off-x (+ MINI-X 5)
        off-y (+ PANEL-Y 22)]
    (for y 0 world/MAP-H
      (for x 0 world/MAP-W
        (let [idx  (+ (* y world/MAP-W) x)
              fogged (fog idx)
              tile (if fogged 255 (world/tile-at tiles x y))
              col  (cond
                     fogged                          COL-BLACK
                     (= tile 1)                      COL-WALL
                     (or (= tile 2) (= tile 3))      COL-DOOR
                     (or (= tile 4) (= tile 5))      COL-GOLD
                     (= tile 6)                      COL-YELLOW
                     COL-FLOOR)]
          (fill ren
                (+ off-x (* x MINI-CELL))
                (+ off-y (* y MINI-CELL))
                (- MINI-CELL 1) (- MINI-CELL 1)
                col))))
    # Player arrow
    (let [px (+ off-x (* (player :x) MINI-CELL) (/ MINI-CELL 2))
          py (+ off-y (* (player :y) MINI-CELL) (/ MINI-CELL 2))]
      (fill ren (- px 3) (- py 3) 6 6 COL-CYAN))))

# ── Title bar ─────────────────────────────────────────────────

(defn draw-title [ren font mode level]
  (fill ren 0 TITLE-Y WIN-W TITLE-H COL-DARK)
  (outline ren 0 TITLE-Y WIN-W TITLE-H COL-SEP)
  (let [hints "Arrows:Move  T:Talk  C:Rest  I:Inv  A:Attack  S:Spell  F:Flee"]
    (text ren font hints 8 8 COL-GRAY)))

# ── Party stats bar ───────────────────────────────────────────

(defn draw-party-bar [ren font party active-idx]
  (fill ren 0 STATS-Y WIN-W STATS-H COL-DARK)
  (outline ren 0 STATS-Y WIN-W STATS-H COL-SEP)
  (let [slot-w (/ WIN-W (length party))]
    (eachp [idx ch] party
      (let [x     (math/floor (* idx slot-w))
            alive (party/alive? ch)
            name-col (cond (not alive) COL-RED
                            (= idx active-idx) COL-CYAN
                            COL-WHITE)]
        (when (= idx active-idx)
          (fill ren x STATS-Y (math/floor slot-w) STATS-H [30 30 60 255]))
        (text ren font (ch :name) (+ x 8) (+ STATS-Y 6) name-col)
        (text ren font (string "Lv" (ch :level) "  HP:" (ch :hp) "/" (ch :hp-max))
              (+ x 8) (+ STATS-Y 22) COL-GRAY)
        (draw-hp-bar ren (+ x 8) (+ STATS-Y 42) (- (math/floor slot-w) 16) 12
                     (ch :hp) (ch :hp-max))
        (when (not alive)
          (text ren font "DEAD" (+ x 8) (+ STATS-Y 58) COL-RED))))))

# ── Message log bar ───────────────────────────────────────────

(defn draw-messages [ren font messages]
  (fill ren 0 MSG-Y WIN-W MSG-H COL-DARK)
  (outline ren 0 MSG-Y WIN-W MSG-H COL-SEP)
  (when (pos? (length messages))
    (text ren font (string "> " (last messages)) 8 (+ MSG-Y 10) COL-GRAY)))

# ── Inventory overlay ─────────────────────────────────────────

(defn draw-inventory [ren font party active-idx]
  (fill ren 100 100 824 568 COL-DARK)
  (outline ren 100 100 824 568 COL-GOLD)
  (text ren font "INVENTORY" 120 116 COL-GOLD)
  (let [ch (party active-idx)]
    (text ren font (string (ch :name) " the " (ch :class)) 120 146 COL-WHITE)
    (text ren font (string "STR:" (ch :str) "  DEX:" (ch :dex) "  CON:" (ch :con)
                            "  INT:" (ch :int) "  WIS:" (ch :wis) "  CHA:" (ch :cha))
          120 172 COL-GRAY)
    (text ren font (string "THAC0:" (ch :thac0) "  AC:" (ch :ac)
                            "  XP:" (ch :xp) "  Level:" (ch :level))
          120 196 COL-GRAY)
    (when (pos? (length (ch :spells)))
      (text ren font "SPELLS:" 120 228 COL-CYAN)
      (eachp [idx sp] (ch :spells)
        (text ren font (string "  " sp) 120 (+ 250 (* idx 18)) COL-WHITE))))
  (text ren font "Press I to close" 120 620 COL-GRAY))

# ── Full-frame render ─────────────────────────────────────────

(defn render-frame [ren font state]
  (let [mode    (state :mode)
        w       (state :world)
        par     (state :party)
        msgs    (state :messages)
        act-idx (or (state :active-idx) 0)
        tiles   (w :tiles)
        fog     (w :fog)
        player  (w :player)
        level   (w :level)]

    # Clear
    (rl/set-color ren 0 0 0 255)
    (rl/clear ren)

    # Panels
    (draw-title ren font mode level)

    (case mode
      :combat
        (let [cs       (state :combat)
              log-lines (combat/combat-log cs)
              monsters  (combat/living-monsters cs)]
          (draw-3d-view ren font tiles player)
          (draw-text-panel ren font log-lines "COMBAT")
          (draw-minimap ren font tiles fog player))

      :dialog
        (let [npc  (state :dialog-npc)
              dlg  (npc :dialog)]
          (draw-3d-view ren font tiles player)
          (draw-text-panel ren font dlg (string (npc :name) " says:"))
          (draw-minimap ren font tiles fog player))

      :inventory
        (do
          (draw-3d-view ren font tiles player)
          (draw-text-panel ren font [] "INVENTORY")
          (draw-minimap ren font tiles fog player)
          (draw-inventory ren font par act-idx))

      # :explore and default
      (do
        (draw-3d-view ren font tiles player)
        (let [loc-name  (if (= level 0) "Solace, Abanasinia" "Ruins of Xak Tsaroth")
              dir-name  (case (player :dir)
                          :north "North" :south "South"
                          :east  "East"  :west  "West" "?")
              area-lines [(string "Location: " loc-name)
                          (string "Facing:   " dir-name)
                          (string "Position: " (player :x) ", " (player :y))]]
          (draw-text-panel ren font area-lines "AREA INFO"))
        (draw-minimap ren font tiles fog player)))

    (draw-party-bar ren font par act-idx)
    (draw-messages  ren font msgs)

    (rl/present ren)))
