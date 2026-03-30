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
(import janet_raylib :as rl)
(import ./world)
(import ./party)
(import ./combat)
(import ./savegame)

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
(def COL-CYAN     [ 60 200 200 255])
(def COL-PANEL-BG [ 10  10  20 255])

# ── Environment colours (ceiling / floor by map type) ─────────
(def ENV-COLORS
  # map-prefix -> [ceiling-color floor-color]
  {:d [[ 40  25  15 255] [ 30  18  10 255]]   # dungeon: dark brown / dark brown
   :i [[ 90  80  70 255] [ 70  65  60 255]]   # interior: brown ceiling / stone gray floor
   :o [[ 90 140 200 255] [ 90  70  50 255]]   # overland: heaven blue ceiling / dirt brown floor
   :w [[ 90 140 200 255] [ 30  80 140 255]]}) # water: heaven blue ceiling / water blue floor
(def COL-SEP      [ 60  55  50 255])

# ── Draw helpers ─────────────────────────────────────────────

(defn- set-col [[r g b a]]
  (rl/set-color r g b a))

(defn- fill [x y w h col]
  (set-col col)
  (rl/fill-rect x y w h))

(defn- outline [x y w h col]
  (set-col col)
  (rl/draw-rect x y w h))

(defn- line [x1 y1 x2 y2 col]
  (set-col col)
  (rl/draw-line x1 y1 x2 y2))

(defn- text [font str x y col]
  (let [[r g b a] col]
    (rl/draw-text font str x y r g b a)))

# ── HP bar helper ────────────────────────────────────────────

(defn- draw-hp-bar [x y w h cur mx]
  (fill x y w h COL-DARK)
  (when (pos? mx)
    (let [frac (/ cur mx)
          col  (cond (> frac 0.5) COL-GREEN
                     (> frac 0.25) COL-YELLOW
                     COL-RED)]
      (fill x y (math/floor (* w frac)) h col)))
  (outline x y w h COL-GRAY))

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
          tile (world/tile-at tiles map-x map-y)
          # Fractional hit position along the wall face — texture U coord
          wall-hit (if (= side :x)
                     (+ py (* (math/abs perp) ray-dy))
                     (+ px (* (math/abs perp) ray-dx)))
          wall-u   (- wall-hit (math/floor wall-hit))]
      [tile (math/abs perp) side wall-u])
    [nil VIEW-DEPTH :x 0.0]))

# ── Compass rose ─────────────────────────────────────────────

(defn- draw-compass [font dir]
  "Draw N/S/E/W compass in the top-right corner of the 3D view."
  (let [cx   (- (+ VIEW-X VIEW-W) 36)   # centre x
        cy   (+ PANEL-Y 36)             # centre y
        r    24                         # outer radius
        # Background circle
        _    (fill (- cx r) (- cy r) (* 2 r) (* 2 r) [0 0 0 160])
        _    (outline (- cx r) (- cy r) (* 2 r) (* 2 r) COL-SEP)
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
        (line cx cy lx2 ly2 (if active COL-CYAN [60 60 60 255]))
        (text font lbl tx ty col)))))

(defn draw-3d-view [font tiles player level tex-config textures]
  # Ceiling and floor — colour by map type prefix (d_ i_ o_ w_)
  (let [level-names {0 "o" 1 "i" 2 "i" 3 "o" 4 "o" 5 "i" 6 "d" 7 "o"
                     8 "d" 9 "i" 10 "o" 11 "i" 12 "o" 13 "w" 14 "o" 15 "i"
                     16 "o" 17 "o" 18 "i" 19 "d"}
        prefix      (keyword (or (level-names level) "o"))
        env         (or (ENV-COLORS prefix) (ENV-COLORS :o))
        col-ceil    (env 0)
        col-floor   (env 1)]
    (fill VIEW-X PANEL-Y VIEW-W (math/floor (/ PANEL-H 2)) col-ceil)
    (fill VIEW-X (+ PANEL-Y (math/floor (/ PANEL-H 2)))
              VIEW-W (math/ceil  (/ PANEL-H 2)) col-floor))

  (let [# Map Y increases downward (row 0 = top of map).
        angle (case (player :dir)
                :east   0.0
                :south  1.5708
                :west   3.1416
                :north  4.7124
                0.0)
        cam-len (math/tan (/ FOV 2))
        dir-x   (math/cos angle)
        dir-y   (math/sin angle)
        plane-x (* (- dir-y) cam-len)
        plane-y (* dir-x     cam-len)
        half    (/ PANEL-H 2)]

    # Floor / ceiling texture overlay — drawn before walls
    (let [floor-tex (get textures (get tex-config :floor))
          ceil-tex  (get textures (get tex-config :ceiling))]
      (rl/draw-floor-ceiling
        floor-tex ceil-tex
        (+ (player :x) 0.5) (+ (player :y) 0.5)
        dir-x dir-y plane-x plane-y
        VIEW-X PANEL-Y VIEW-W PANEL-H))

    (for screen-x 0 VIEW-W
      (let [cam-x  (- (* 2 (/ screen-x VIEW-W)) 1)
            ray-dx (+ dir-x (* plane-x cam-x))
            ray-dy (+ dir-y (* plane-y cam-x))
            # +0.5 places the ray origin at tile centre
            [tile perp-dist side wall-u]
              (dda-cast tiles (+ (player :x) 0.5) (+ (player :y) 0.5) ray-dx ray-dy)]
        (when (and tile (> perp-dist 0))
          (let [wall-h  (math/floor (/ PANEL-H perp-dist))
                top     (math/floor (- half (/ wall-h 2)))
                base    (math/floor (* 255 (max 0 (- 1 (/ perp-dist VIEW-DEPTH)))))
                shade   (if (= side :y) (math/floor (* base 0.7)) base)
                draw-top    (max 0 top)
                draw-bottom (min PANEL-H (+ top wall-h))
                draw-h      (- draw-bottom draw-top)
                # Pick texture name: door tiles use :door, walls use :wall
                tex-name (if (or (= tile 2) (= tile 3))
                           (get tex-config :door)
                           (get tex-config :wall))
                wall-tex (and tex-name (get textures tex-name))]
            (when (> draw-h 0)
              (if wall-tex
                # Textured wall strip — shade tints the texture by distance
                (rl/draw-texture-strip wall-tex wall-u
                                       (+ VIEW-X screen-x)
                                       (+ PANEL-Y draw-top)
                                       draw-h shade shade shade)
                # Fallback: solid colour (original behaviour)
                (let [col-shade (cond
                                  (= tile 2) [shade (math/floor (* shade 0.6)) 0 255]
                                  (= tile 1) [shade shade (math/floor (* shade 0.8)) 255]
                                  [(math/floor (* shade 0.8)) shade (math/floor (* shade 0.6)) 255])]
                  (set-col col-shade)
                  (rl/fill-rect (+ VIEW-X screen-x) (+ PANEL-Y draw-top) 1 draw-h))))))))

  # Compass overlay — drawn after walls so it's always on top
  (draw-compass font (player :dir))))

# ── Isometric combat view ────────────────────────────────────
#
# Gold Box-style tactical battlefield shown when an encounter starts.
# Replaces the 3D first-person view for the duration of combat.
#
# Grid: 12 columns × 8 rows of isometric diamond tiles.
# Heroes are placed on the left (cols 1-2), monsters on the right (cols 8-10).
# The active combatant is highlighted with a yellow ring.
#
# Coordinate mapping (standard isometric, y-down screen space):
#   screen_x = origin_x + (col - row) * TILE-W/2
#   screen_y = origin_y + (col + row) * TILE-H/2

(def ISO-COLS 12)
(def ISO-ROWS  8)
(def ISO-TW   44)   # full diamond width  in pixels
(def ISO-TH   22)   # full diamond height in pixels

(defn- iso->screen [ox oy col row]
  [(math/floor (+ ox (* (- col row) (/ ISO-TW 2))))
   (math/floor (+ oy (* (+ col row) (/ ISO-TH 2))))])

(defn- draw-iso-tile [ox oy col row]
  "Draw one checkered floor tile."
  (let [[cx cy] (iso->screen ox oy col row)
        hw      (/ ISO-TW 2)
        hh      (/ ISO-TH 2)
        checker (% (+ col row) 2)
        fc      (if (= checker 0) [60 54 44 255] [48 43 36 255])]
    (set-col fc)
    (rl/fill-diamond cx cy hw hh)
    (set-col [76 68 56 255])
    (rl/draw-diamond-lines cx cy hw hh)))

(defn draw-iso-combat-view [font combat-state]
  # Grid origin — top vertex of tile (0,0), centred horizontally in the view.
  # The full grid spans (COLS+ROWS)*TW/2 wide and (COLS+ROWS)*TH/2 tall.
  (let [ox  (+ VIEW-X (math/floor (/ VIEW-W 2)))
        oy  (+ PANEL-Y 28)
        cs  combat-state
        pos (cs :positions)      # {combatant-idx [col row]}
        combs (cs :combatants)
        n   (length combs)
        turn (if (pos? n) (% (cs :turn-idx) n) 0)]

    # ── Background ──────────────────────────────────────────────
    (fill VIEW-X PANEL-Y VIEW-W PANEL-H [14 11 9 255])

    # ── Floor tiles (back-to-front row order) ───────────────────
    (for row 0 ISO-ROWS
      (for col 0 ISO-COLS
        (draw-iso-tile ox oy col row)))

    # ── Combatants — sorted back-to-front for correct z-order ──
    (def entries (array/slice (pairs pos)))
    (sort-by (fn [[_ [c r]]] (+ c r)) entries)

    (each [idx [col row]] entries
      (when (< idx (length combs))
        (let [c       (combs idx)
              is-hero (= :hero (c :kind))
              alive   ((c :ref) :alive)
              active  (= idx turn)
              [cx cy] (iso->screen ox oy col row)
              # Figure is slightly smaller than the tile
              hw      (- (/ ISO-TW 2) 5)
              hh      (- (/ ISO-TH 2) 3)
              body-col (cond
                         (not alive) [55 32 32 255]
                         active      (if is-hero [110 225 255 255]
                                                 [255 145 55 255])
                         is-hero     [75 155 225 255]
                         [215 72 52 255])]

          # Drop shadow for depth
          (set-col [0 0 0 90])
          (rl/fill-diamond cx (+ cy 4) (- hw 2) (- hh 1))

          # Figure body
          (set-col body-col)
          (rl/fill-diamond cx cy hw hh)

          # Bright pulsing ring around the active combatant
          (when active
            (set-col COL-YELLOW)
            (rl/draw-diamond-lines cx cy (+ hw 4) (+ hh 3))
            (set-col [255 255 180 120])
            (rl/draw-diamond-lines cx cy (+ hw 6) (+ hh 5)))

          # Initial letter
          (when alive
            (text font (string/slice (c :name) 0 1)
                  (- cx 4) (- cy 8)
                  (if active COL-DARK COL-WHITE)))

          # Skull / X for dead
          (when (not alive)
            (set-col [180 40 40 200])
            (rl/draw-diamond-lines cx cy hw hh)
            (text font "X" (- cx 4) (- cy 8) COL-RED)))))

    # ── Turn indicator banner ────────────────────────────────────
    (when (pos? n)
      (let [active-c (combs turn)
            banner   (string (active-c :name) "'s turn")]
        (fill VIEW-X PANEL-Y VIEW-W 22 [20 16 10 200])
        (text font banner (+ VIEW-X 8) (+ PANEL-Y 5) COL-GOLD)))

    # ── Legend ───────────────────────────────────────────────────
    (let [lx (+ VIEW-X 8)
          ly (+ PANEL-Y PANEL-H -42)]
      (fill VIEW-X (- (+ PANEL-Y PANEL-H) 46) 120 46 [10 8 6 180])
      (set-col [75 155 225 255])
      (rl/fill-diamond (+ lx 8) (+ ly 7) 7 4)
      (text font "Hero" (+ lx 18) (+ ly 1) COL-GRAY)
      (set-col [215 72 52 255])
      (rl/fill-diamond (+ lx 8) (+ ly 24) 7 4)
      (text font "Enemy" (+ lx 18) (+ ly 18) COL-GRAY))))

# ── Text / combat panel ───────────────────────────────────────

(defn draw-text-panel [font lines title]
  (fill TEXT-X PANEL-Y TEXT-W PANEL-H COL-PANEL-BG)
  (outline TEXT-X PANEL-Y TEXT-W PANEL-H COL-SEP)
  (text font title (+ TEXT-X 8) (+ PANEL-Y 6) COL-GOLD)
  (line TEXT-X (+ PANEL-Y 22) (+ TEXT-X TEXT-W) (+ PANEL-Y 22) COL-SEP)
  (var ly (+ PANEL-Y 30))
  (each ln lines
    (text font ln (+ TEXT-X 8) ly COL-WHITE)
    (set ly (+ ly 18))))

# ── Minimap ───────────────────────────────────────────────────

(def MINI-CELL 12)    # pixels per map cell

(defn draw-minimap [font tiles fog player]
  (fill MINI-X PANEL-Y MINI-W PANEL-H COL-DARK)
  (outline MINI-X PANEL-Y MINI-W PANEL-H COL-SEP)
  (text font "MAP" (+ MINI-X 8) (+ PANEL-Y 6) COL-GOLD)
  (let [off-x (+ MINI-X 5)
        off-y (+ PANEL-Y 22)]
    (for y 0 world/MAP-H
      (for x 0 world/MAP-W
        (let [idx  (+ (* y world/MAP-W) x)
              fogged (fog idx)
              tile (if fogged 255 (world/tile-at tiles x y))
              col  (cond
                     fogged                          [0 0 0 255]
                     (= tile 1)                      COL-WALL
                     (or (= tile 2) (= tile 3))      COL-DOOR
                     (or (= tile 4) (= tile 5))      COL-GOLD
                     (= tile 6)                      COL-YELLOW
                     COL-FLOOR)]
          (fill (+ off-x (* x MINI-CELL))
                (+ off-y (* y MINI-CELL))
                (- MINI-CELL 1) (- MINI-CELL 1)
                col))))
    # Player arrow
    (let [px (+ off-x (* (player :x) MINI-CELL) (/ MINI-CELL 2))
          py (+ off-y (* (player :y) MINI-CELL) (/ MINI-CELL 2))]
      (fill (- px 3) (- py 3) 6 6 COL-CYAN))))

# ── Title bar ─────────────────────────────────────────────────

(defn draw-title [font mode level]
  (fill 0 TITLE-Y WIN-W TITLE-H COL-DARK)
  (outline 0 TITLE-Y WIN-W TITLE-H COL-SEP)
  (let [hints "Arrows:Move  T:Talk  C:Rest  I:Inv  A:Attack  S:Spell  F:Flee  F10:Save/Load  ESC:Quit"]
    (text font hints 8 8 COL-GRAY)))

# ── Party stats bar ───────────────────────────────────────────

(defn draw-party-bar [font party active-idx]
  (fill 0 STATS-Y WIN-W STATS-H COL-DARK)
  (outline 0 STATS-Y WIN-W STATS-H COL-SEP)
  (let [slot-w (/ WIN-W (length party))]
    (eachp [idx ch] party
      (let [x     (math/floor (* idx slot-w))
            alive (party/alive? ch)
            name-col (cond (not alive) COL-RED
                            (= idx active-idx) COL-CYAN
                            COL-WHITE)]
        (when (= idx active-idx)
          (fill x STATS-Y (math/floor slot-w) STATS-H [30 30 60 255]))
        (text font (ch :name) (+ x 8) (+ STATS-Y 6) name-col)
        (text font (string "Lv" (ch :level) "  HP:" (ch :hp) "/" (ch :hp-max))
              (+ x 8) (+ STATS-Y 22) COL-GRAY)
        (draw-hp-bar (+ x 8) (+ STATS-Y 42) (- (math/floor slot-w) 16) 12
                     (ch :hp) (ch :hp-max))
        (when (not alive)
          (text font "DEAD" (+ x 8) (+ STATS-Y 58) COL-RED))))))

# ── Message log bar ───────────────────────────────────────────

(defn draw-messages [font messages]
  (fill 0 MSG-Y WIN-W MSG-H COL-DARK)
  (outline 0 MSG-Y WIN-W MSG-H COL-SEP)
  (when (pos? (length messages))
    (text font (string "> " (last messages)) 8 (+ MSG-Y 10) COL-GRAY)))

# ── Inventory overlay ─────────────────────────────────────────

(defn draw-inventory [font party active-idx]
  # Dark backdrop over full screen
  (fill 0 0 WIN-W WIN-H [0 0 0 180])
  (fill 100 100 824 568 COL-DARK)
  (outline 100 100 824 568 COL-GOLD)
  (text font "INVENTORY" 120 116 COL-GOLD)
  (let [ch (party active-idx)]
    (text font (string (ch :name) " the " (ch :class)) 120 146 COL-WHITE)
    (text font (string "STR:" (ch :str) "  DEX:" (ch :dex) "  CON:" (ch :con)
                            "  INT:" (ch :int) "  WIS:" (ch :wis) "  CHA:" (ch :cha))
          120 172 COL-GRAY)
    (text font (string "THAC0:" (ch :thac0) "  AC:" (ch :ac)
                            "  XP:" (ch :xp) "  Level:" (ch :level))
          120 196 COL-GRAY)
    (when (pos? (length (ch :spells)))
      (text font "SPELLS:" 120 228 COL-CYAN)
      (eachp [idx sp] (ch :spells)
        (text font (string "  " sp) 120 (+ 250 (* idx 18)) COL-WHITE))))
  (text font "Press I to close" 120 620 COL-GRAY))

# ── Save / Load menu overlay ──────────────────────────────────

(defn draw-savemenu [font state]
  "Draw the 10-slot save/load overlay covering the full screen height."
  (let [bx   80    # box x
        by   60    # box y — high enough to cover everything incl. party bar
        bw  864    # box width
        bh  648    # box height — extends to bottom of screen
        act  (state :save-selected)
        naming (state :save-naming)   # true when typing a name
        name-buf (or (state :save-name-buf) "")]

    # Dark semi-transparent backdrop over entire screen
    (fill 0 0 WIN-W WIN-H [0 0 0 180])

    # Panel
    (fill    bx by bw bh COL-DARK)
    (outline bx by bw bh COL-GOLD)

    # Title
    (text font "SAVE / LOAD GAME" (+ bx 300) (+ by 12) COL-GOLD)
    (line bx (+ by 34) (+ bx bw) (+ by 34) COL-SEP)

    # Instructions
    (if naming
      (do
        (text font "Enter save name  a-z 0-9 - .  (Enter confirm, ESC cancel):"
              (+ bx 16) (+ by 42) COL-YELLOW)
        (text font (string "> " name-buf "_") (+ bx 16) (+ by 60) COL-WHITE))
      (text font
            "S:Save  L:Load  DEL:Delete  ↑↓:Select slot  ESC:Close"
            (+ bx 16) (+ by 42) COL-GRAY))

    # 10 slots
    (for i 0 savegame/NUM-SLOTS
      (let [sy      (+ by 84 (* i 56))
            info    (savegame/slot-info i)
            selected (= i act)
            bg-col  (if selected [40 40 80 255] [15 15 30 255])
            txt-col (if selected COL-CYAN COL-WHITE)]
        (fill    (+ bx 16) sy (- bw 32) 50 bg-col)
        (outline (+ bx 16) sy (- bw 32) 50
                 (if selected COL-CYAN COL-SEP))
        (text font info (+ bx 28) (+ sy 16) txt-col)))))

# ── Start Screen ─────────────────────────────────────────────
#
# Shown at launch before the game world is entered.
# Selection: N = New Game  L = Load  ↑↓ = move cursor  Enter = confirm

(def STARTSCREEN-FLAVOR
  ["The War of the Lance has begun."
   "Takhisis, the Dragon Queen, stirs beneath the world."
   "Five Dragonarmies march across Krynn."
   "Only the Heroes of the Lance stand against the darkness."
   ""
   "Your journey begins in Solace, Abanasinia."])

(defn draw-startscreen [font selected-idx]
  # Full black backdrop
  (fill 0 0 WIN-W WIN-H [0 0 0 255])

  # Outer gold border — two nested rectangles for thickness
  (outline  16  16 (- WIN-W 32) (- WIN-H 32) COL-GOLD)
  (outline  20  20 (- WIN-W 40) (- WIN-H 40) COL-SEP)

  # ── Header band ─────────────────────────────────────────────
  (fill 32 32 (- WIN-W 64) 80 [10 8 4 255])
  (outline 32 32 (- WIN-W 64) 80 COL-GOLD)

  # Title and subtitle — centred in the 1024px window
  # DejaVu Mono 16px => approx 9px per glyph; window centre = 512
  (let [title    "GOLD  BOX  ENGINE"
        subtitle "Dragonlance  -  War of the Lance"
        ch-w     9
        title-x    (- 512 (math/floor (/ (* (length title)    ch-w) 2)))
        sub-x      (- 512 (math/floor (/ (* (length subtitle) ch-w) 2)))]
    (text font title    title-x 44 COL-GOLD)
    (line title-x 68 (+ title-x (* (length title) ch-w)) 68 COL-GOLD)
    (text font subtitle sub-x   74 COL-GRAY))

  # ── Decorative dragon silhouette (ASCII) ─────────────────────
  (let [art ["     /\\_____/\\"
             "   /  o   o  \\"
             "  ( ==  ^  == )"
             "   )         ("
             "  (           )"
             "   ( (  )  ) )"
             "  (__(__)(__))"]
        ax 420  ay 140]
    (eachp [i ln] art
      (text font ln ax (+ ay (* i 16)) [80 60 20 255])))

  # ── Flavour text ──────────────────────────────────────────────
  (let [fy 140]
    (eachp [i ln] STARTSCREEN-FLAVOR
      (text font ln 80 (+ fy (* i 20)) COL-GRAY)))

  # ── Buttons ───────────────────────────────────────────────────
  (def btn-w 320)
  (def btn-h  64)
  (def btn-x (- (/ WIN-W 2) (/ btn-w 2)))
  (def buttons [["N  :  NEW GAME"  :new]
                ["L  :  LOAD GAME" :load]])

  (eachp [idx [label _]] buttons
    (let [by      (+ 490 (* idx 90))
          active  (= idx selected-idx)
          bg-col  (if active [40 35 10 255]  [12 10 4 255])
          brd-col (if active COL-GOLD        COL-SEP)
          txt-col (if active COL-GOLD        COL-GRAY)]
      (fill    btn-x by btn-w btn-h bg-col)
      (outline btn-x by btn-w btn-h brd-col)
      # Inner decorative line
      (outline (+ btn-x 4) (+ by 4) (- btn-w 8) (- btn-h 8) brd-col)
      # Selection arrow
      (when active
        (text font ">" (- btn-x 22) (+ by 22) COL-GOLD))
      (text font label (+ btn-x 60) (+ by 22) txt-col)))

  # ── Footer hint ───────────────────────────────────────────────
  (let [hint "↑ ↓  or  N / L  to select     ENTER  to confirm     ESC  to quit"]
    (text font hint 200 (- WIN-H 44) COL-GRAY))

  # Bottom border line above hint
  (line 32 (- WIN-H 56) (- WIN-W 32) (- WIN-H 56) COL-SEP))

# ── Full-frame render ─────────────────────────────────────────

(defn render-frame [font state textures]
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
    (rl/set-color 0 0 0 255)
    (rl/clear)

    # Start screen — full-screen, skip all game panels
    (when (= mode :startscreen)
      (draw-startscreen font (or (state :start-selected) 0))
      (rl/present)
      (break))

    # Panels
    (draw-title font mode level)

    (case mode
      :combat
        (let [cs       (state :combat)
              log-lines (combat/combat-log cs)
              monsters  (combat/living-monsters cs)]
          (draw-iso-combat-view font cs)
          (draw-text-panel font log-lines "COMBAT")
          (draw-minimap font tiles fog player))

      :dialog
        (let [npc  (state :dialog-npc)
              dlg  (npc :dialog)]
          (draw-3d-view font tiles player level (world/level-tex-config level) textures)
          (draw-text-panel font dlg (string (npc :name) " says:"))
          (draw-minimap font tiles fog player))

      :inventory
        (do
          (draw-3d-view font tiles player level (world/level-tex-config level) textures)
          (draw-text-panel font [] "INVENTORY")
          (draw-minimap font tiles fog player))

      # :explore and default
      (do
        (draw-3d-view font tiles player level (world/level-tex-config level) textures)
        (let [level-display
              {0  "Solace, Abanasinia"      1  "Inn of the Last Home"
               2  "Tika's Room"             3  "Darken Wood"
               4  "Que-Shu Plains"          5  "Chieftain's Hut"
               6  "Crystal Cave"            7  "Xak Tsaroth Ruins"
               8  "Xak Tsaroth Depths"      9  "Mishakal's Temple"
               10 "Qualinesti"              11 "Speaker's Palace"
               12 "Sea of Blood Coast"      13 "The New Sea"
               14 "Tarsis"                  15 "Library of Tarsis"
               16 "Ergoth Coast"            17 "Pax Tharkas"
               18 "Great Hall of Pax Tharkas" 19 "Dungeons of Pax Tharkas"}
              loc-name  (or (level-display level) (string "Level " level))
              dir-name  (case (player :dir)
                          :north "North" :south "South"
                          :east  "East"  :west  "West" "?")
              area-lines [(string "Location: " loc-name)
                          (string "Facing:   " dir-name)
                          (string "Position: " (player :x) ", " (player :y))]]
          (draw-text-panel font area-lines "AREA INFO"))
        (draw-minimap font tiles fog player)))

    (draw-party-bar font par act-idx)
    (draw-messages font msgs)

    # Overlays — drawn last so they cover the party bar
    (when (= mode :inventory)
      (draw-inventory font par act-idx))
    (when (= mode :savemenu)
      (draw-savemenu font state))

    (rl/present)))
