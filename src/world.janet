# world.janet — tile maps, entity system, dungeon loader
#
# Maps are loaded from  ../maps/*.map  at runtime.
# Tile codes (internal integers):
#   0  floor     1  wall      2  door (closed)
#   3  door (open)  4  stairs down  5  stairs up  6  chest
#
# Map file format:
#   level N
#   spawn X Y dir
#   map / endmap  — 16x16 grid of tile characters
#       # wall  . floor  D door  d open-door  > stairs-down  < stairs-up  C chest
#   npc ID "Name" X Y / endnpc  — NPC with dialog lines

(def MAP-W 16)
(def MAP-H 16)

# ── Tile character → integer ──────────────────────────────────

(def CHAR-TILE
  {"#" 1  "." 0  "D" 2  "d" 3  ">" 4  "<" 5  "C" 6})

# ── Map file parser ───────────────────────────────────────────

(defn- parse-map-file [path]
  "Parse a .map file. Returns a table:
   {:level N  :spawn [x y dir]  :tiles array  :npcs array}"
  (def result @{:level 0 :spawn [1 1 :north] :tiles @[] :npcs @[]})
  (def lines (string/split "\n" (slurp path)))

  (var mode :header)      # :header | :map | :npc
  (var map-rows @[])
  (var cur-npc nil)

  (each raw-line lines
    (def line (string/trim raw-line))
    # Skip blank lines and comments — but ONLY outside map/npc blocks.
    # Inside a map block, '#' is the wall tile character, not a comment.
    (when (and (not= line "")
               (or (= mode :map) (= mode :npc)
                   (not (string/has-prefix? "#" line))))
      (cond
        # ── header directives ────────────────────────────────
        (string/has-prefix? "level " line)
          (put result :level (scan-number (string/trim (string/slice line 6))))

        (string/has-prefix? "spawn " line)
          (let [parts (filter |(not= $ "") (string/split " " line))
                x   (scan-number (parts 1))
                y   (scan-number (parts 2))
                dir (keyword (parts 3))]
            (put result :spawn [x y dir]))

        # ── map block ─────────────────────────────────────────
        (= line "map")
          (set mode :map)

        (= line "endmap")
          (do
            # Flatten the rows into a tile array
            (each row map-rows
              (for col 0 MAP-W
                (let [ch (string/slice row col (+ col 1))
                      tile (or (CHAR-TILE ch) 0)]
                  (array/push (result :tiles) tile))))
            (set mode :header))

        (= mode :map)
          (array/push map-rows line)

        # ── npc block ─────────────────────────────────────────
        (string/has-prefix? "npc " line)
          (do
            (def parts (string/split " " line))
            # parts: ["npc" id "\"Name\"" x y]  — name may be quoted
            # Find the quoted name
            (def id (keyword (parts 1)))
            (def name-start (string/find "\"" line))
            (def name-end   (string/find "\"" line (+ name-start 1)))
            (def npc-name   (string/slice line (+ name-start 1) name-end))
            # x and y come after the closing quote
            (def after-name (string/trim (string/slice line (+ name-end 1))))
            (def xy-parts   (filter |(not= $ "") (string/split " " after-name)))
            (def nx (scan-number (xy-parts 0)))
            (def ny (scan-number (xy-parts 1)))
            (set cur-npc @{:id id :name npc-name :x nx :y ny :dialog @[]})
            (set mode :npc))

        (= line "endnpc")
          (do
            (array/push (result :npcs) cur-npc)
            (set cur-npc nil)
            (set mode :header))

        (= mode :npc)
          (array/push (cur-npc :dialog) line))))

  result)

# ── Level registry ─────────────────────────────────────────────
# Maps are loaded once and cached here.

(var *level-cache* @{})

(defn- load-level [map-path]
  (if (get *level-cache* map-path)
    (*level-cache* map-path)
    (let [data (parse-map-file map-path)]
      (put *level-cache* map-path data)
      data)))

# Resolve path relative to this source file's directory
# Janet scripts run from src/, so maps are at ../maps/
(def MAP-DIR "../maps")

(def LEVEL-FILES
  {0 (string MAP-DIR "/solace.map")
   1 (string MAP-DIR "/xak-tsaroth.map")})

# ── Monster spawn tables ──────────────────────────────────────

(def MONSTER-DEFS
  {:baaz-draconian  @{:name "Baaz Draconian"  :hp 18 :hp-max 18 :ac 4
                      :thac0 18 :xp 65  :alive true}
   :kapak-draconian @{:name "Kapak Draconian" :hp 22 :hp-max 22 :ac 4
                      :thac0 17 :xp 120 :alive true}
   :bozak-draconian @{:name "Bozak Draconian" :hp 26 :hp-max 26 :ac 3
                      :thac0 16 :xp 270 :alive true}
   :sivak-draconian @{:name "Sivak Draconian" :hp 34 :hp-max 34 :ac 1
                      :thac0 15 :xp 650 :alive true}
   :aurak-draconian @{:name "Aurak Draconian" :hp 40 :hp-max 40 :ac 2
                      :thac0 14 :xp 975 :alive true}
   :blue-dragon     @{:name "Blue Dragon"     :hp 88 :hp-max 88 :ac -1
                      :thac0 10 :xp 7000 :alive true}})

(defn make-monster [kind]
  (merge @{} (MONSTER-DEFS kind)))

(def ENCOUNTER-TABLE
  {0 [[:baaz-draconian :baaz-draconian :baaz-draconian]
      [:kapak-draconian :baaz-draconian]
      [:kapak-draconian :kapak-draconian]]
   1 [[:bozak-draconian :sivak-draconian]
      [:sivak-draconian :sivak-draconian :baaz-draconian]
      [:aurak-draconian :bozak-draconian]
      [:blue-dragon]]})

# ── Map accessors ─────────────────────────────────────────────

(defn tile-at [tiles x y]
  (tiles (+ (* y MAP-W) x)))

(defn set-tile! [tiles x y v]
  (put tiles (+ (* y MAP-W) x) v))

(defn passable? [tiles x y]
  (let [t (tile-at tiles x y)]
    (or (= t 0) (= t 2) (= t 3) (= t 4) (= t 5) (= t 6))))

# ── Direction helpers ─────────────────────────────────────────

(def DIR-DELTA
  {:north [0 -1] :south [0 1] :east [1 0] :west [-1 0]})

(def TURN-LEFT
  {:north :west :west :south :south :east :east :north})

(def TURN-RIGHT
  {:north :east :east :south :south :west :west :north})

(defn facing-delta [dir] (DIR-DELTA dir))

(defn turn-left!  [player] (put player :dir (TURN-LEFT  (player :dir))))
(defn turn-right! [player] (put player :dir (TURN-RIGHT (player :dir))))

(defn- open-door-if-needed! [tiles x y]
  "If (x,y) is a closed door, open it."
  (when (= (tile-at tiles x y) 2)
    (set-tile! tiles x y 3)))

(defn move-forward! [tiles player]
  (let [[dx dy] (facing-delta (player :dir))
        nx (+ (player :x) dx)
        ny (+ (player :y) dy)]
    (when (passable? tiles nx ny)
      (open-door-if-needed! tiles nx ny)
      (put player :x nx)
      (put player :y ny)
      true)))

(defn move-backward! [tiles player]
  (let [[dx dy] (facing-delta (player :dir))
        nx (- (player :x) dx)
        ny (- (player :y) dy)]
    (when (passable? tiles nx ny)
      (open-door-if-needed! tiles nx ny)
      (put player :x nx)
      (put player :y ny)
      true)))

# ── NPC lookup ────────────────────────────────────────────────

(defn npc-at [entities x y]
  (find |(and (= ($ :x) x) (= ($ :y) y) ($ :dialog)) entities))

# ── Random encounter ──────────────────────────────────────────

(defn encounter-check? []
  "Return true ~1/32 moves on average."
  (= 0 (% (math/floor (* (math/random) 32)) 32)))

(defn random-encounter [level]
  (let [table (ENCOUNTER-TABLE level)
        group (table (% (math/floor (* (math/random) (length table))) (length table)))]
    (map make-monster group)))

# ── World factory ─────────────────────────────────────────────

(defn- level-data [level-num]
  (load-level (LEVEL-FILES level-num)))

(defn- make-entities [npcs]
  (array/slice (map |(merge @{} $) npcs)))

(defn make-world []
  (let [data (level-data 0)
        [sx sy sdir] (data :spawn)]
    @{:level    0
      :tiles    (array/slice (data :tiles))
      :entities (make-entities (data :npcs))
      :fog      (array/new-filled (* MAP-W MAP-H) true)
      :player   @{:x sx :y sy :dir sdir}}))

(defn descend! [world]
  (let [data (level-data 1)
        [sx sy sdir] (data :spawn)]
    (put world :level 1)
    (put world :tiles    (array/slice (data :tiles)))
    (put world :entities (make-entities (data :npcs)))
    (put world :fog      (array/new-filled (* MAP-W MAP-H) true))
    (put (world :player) :x sx)
    (put (world :player) :y sy)
    (put (world :player) :dir sdir)))

(defn ascend! [world]
  (let [data (level-data 0)
        [sx sy sdir] (data :spawn)]
    (put world :level 0)
    (put world :tiles    (array/slice (data :tiles)))
    (put world :entities (make-entities (data :npcs)))
    (put world :fog      (array/new-filled (* MAP-W MAP-H) true))
    (put (world :player) :x sx)
    (put (world :player) :y sy)
    (put (world :player) :dir sdir)))

(defn reveal-fog! [world]
  "Mark the 3x3 cells around the player as explored."
  (let [px (get-in world [:player :x])
        py (get-in world [:player :y])]
    (for dy -1 2
      (for dx -1 2
        (let [fx (+ px dx) fy (+ py dy)]
          (when (and (>= fx 0) (< fx MAP-W) (>= fy 0) (< fy MAP-H))
            (put (world :fog) (+ (* fy MAP-W) fx) false)))))))
