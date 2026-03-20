# world.janet — tile maps, entity system, dungeon loader
#
# Maps are loaded from  ../maps/<name>.map  at runtime.
#
# Tile codes (internal integers):
#   0 floor   1 wall   2 door(closed)   3 door(open)
#   4 stairs-down / exit-forward (>)
#   5 stairs-up   / exit-back    (<)
#   6 chest
#   7 port / dock (P)
#
# Map file format:
#   level N
#   spawn X Y dir
#   map / endmap  — 16×16 grid of tile characters
#   npc ID "Name" X Y / endnpc  — NPC with dialog lines

(def MAP-W 16)
(def MAP-H 16)

# ── Level registry ─────────────────────────────────────────────
# Maps 0-19, named by prefix convention:
#   o_ overland   i_ interior/castle   d_ dungeon   w_ water

(def LEVEL-FILES
  {0  "o_solace"
   1  "i_inn_last_home"
   2  "i_tika_house"
   3  "o_darken_wood"
   4  "o_que_shu"
   5  "i_chieftain_hut"
   6  "d_crystal_cave"
   7  "o_xak_tsaroth"
   8  "d_xak_tsaroth"
   9  "i_xak_tsaroth_temple"
   10 "o_qualinesti"
   11 "i_qualinesti_palace"
   12 "o_sea_blood_coast"
   13 "w_newsea"
   14 "o_tarsis"
   15 "i_tarsis_library"
   16 "o_ergoth_coast"
   17 "o_pax_tharkas"
   18 "i_pax_tharkas_hall"
   19 "d_pax_tharkas"})

# ── Connection table ────────────────────────────────────────────
# Format: {from-level {tile-code to-level}}
# Tile codes: 2=door  4=stairs-down/>  5=stairs-up/<  7=port/P
#
# World graph (Dragonlance — War of the Lance):
#
#  o_solace(0) --D--> i_inn(1) --D--> i_tika(2)
#       |>
#  o_darken_wood(3) --D--> o_qualinesti(10) --D--> i_palace(11)
#       |>                       |>
#  o_que_shu(4) --D--> i_chieftain(5)   o_sea_coast(12) --P--> w_newsea(13)
#       |>      --P--> d_crystal(6)           |>
#  o_xak_tsaroth(7) --D--> i_temple(9)   o_tarsis(14) --D--> i_library(15)
#       |>                                    |P           |>
#  d_xak_tsaroth(8)                    o_ergoth(16)   o_pax_tharkas(17) --D--> i_hall(18)
#                                                          |>
#                                                     d_pax_tharkas(19)

# CONNECTIONS format: {from-level {tile-code [dest-level arr-x arr-y arr-dir]}}
# Arrival is ON the return-exit tile in the destination map, facing into the map.

(def CONNECTIONS
  {
    0 {2 [ 1  1  1 :south] 4 [ 3  5 14 :north]}
    1 {2 [ 2  7 14 :north] 5 [ 0  8  3 :south]}
    2 {5 [ 1 13 14 :north]}
    3 {2 [10  8 14 :north] 4 [ 4  5 14 :north] 5 [ 0 14 14 :north]}
    4 {2 [ 5  7 14 :north] 4 [ 7  7 14 :north] 5 [ 3 13 14 :north] 7 [ 6  2 14 :north]}
    5 {5 [ 4  6  5 :south]}
    6 {5 [ 4  6  1 :south]}
    7 {2 [ 9  2 14 :north] 4 [ 8  7 14 :north] 5 [ 4 13 14 :north]}
    8 {5 [ 7  8 13 :north]}
    9 {5 [ 7  7  6 :south]}
   10 {2 [11  8 14 :north] 4 [12  8 14 :north] 5 [ 3  6  1 :south]}
   11 {5 [10  7  1 :south]}
   12 {4 [14  8 13 :north] 5 [10 14 13 :north] 7 [13  8  7 :south]}
   13 {7 [12 13 11 :west]}
   14 {2 [15  7 14 :north] 4 [17  7 13 :north] 5 [12 13 13 :north] 7 [16  7  7 :south]}
   15 {5 [14  2  3 :east]}
   16 {7 [14  6  1 :south]}
   17 {2 [18  7 14 :north] 4 [19  7 14 :north] 5 [14 14 14 :north]}
   18 {5 [17  7  7 :south]}
   19 {5 [17  7 11 :south]}
  })

(defn get-connection [level tile]
  "Return [dest-level arr-x arr-y arr-dir] or nil."
  (get-in CONNECTIONS [level tile]))

# ── Tile character → integer ───────────────────────────────────

(def CHAR-TILE
  {"#" 1  "." 0  "D" 2  "d" 3  ">" 4  "<" 5  "C" 6  "P" 7})

# ── Map file parser ────────────────────────────────────────────

(defn- parse-map-file [path]
  (def result @{:level 0 :spawn [1 1 :north] :tiles @[] :npcs @[]})
  (def lines (string/split "\n" (slurp path)))
  (var mode :header)
  (var map-rows @[])
  (var cur-npc nil)
  (each raw-line lines
    (def line (string/trim raw-line))
    (when (and (not= line "")
               (or (= mode :map) (= mode :npc)
                   (not (string/has-prefix? "#" line))))
      (cond
        (string/has-prefix? "level " line)
          (put result :level (scan-number (string/trim (string/slice line 6))))
        (string/has-prefix? "spawn " line)
          (let [parts (filter |(not= $ "") (string/split " " line))
                x   (scan-number (parts 1))
                y   (scan-number (parts 2))
                dir (keyword (parts 3))]
            (put result :spawn [x y dir]))
        (= line "map")
          (set mode :map)
        (= line "endmap")
          (do
            (each row map-rows
              (for col 0 MAP-W
                (let [ch (string/slice row col (+ col 1))
                      tile (or (CHAR-TILE ch) 0)]
                  (array/push (result :tiles) tile))))
            (set mode :header))
        (= mode :map)
          (array/push map-rows line)
        (string/has-prefix? "npc " line)
          (do
            (def name-start (string/find "\"" line))
            (def name-end   (string/find "\"" line (+ name-start 1)))
            (def npc-name   (string/slice line (+ name-start 1) name-end))
            (def after      (string/trim (string/slice line (+ name-end 1))))
            (def parts      (filter |(not= $ "") (string/split " " after)))
            (def id (keyword (string/trim (string/slice line 4 name-start))))
            (def nx (scan-number (parts 0)))
            (def ny (scan-number (parts 1)))
            (set cur-npc @{:id id :name npc-name :x nx :y ny :dialog @[]})
            (set mode :npc))
        (= line "endnpc")
          (do (array/push (result :npcs) cur-npc)
              (set cur-npc nil)
              (set mode :header))
        (= mode :npc)
          (array/push (cur-npc :dialog) line))))
  result)

# ── Level cache ────────────────────────────────────────────────

(var *cache* @{})

(defn- find-map-dir []
  (var found "../maps")
  (each c ["../maps" "./maps" (string (os/cwd) "/maps")]
    (when (and (= found "../maps") (os/stat c))
      (set found c)))
  found)

(defn- load-level [level-num]
  (if (get *cache* level-num)
    (*cache* level-num)
    (do
      (def name (LEVEL-FILES level-num))
      (def data (parse-map-file (string (find-map-dir) "/" name ".map")))
      (put *cache* level-num data)
      data)))

# ── Monster spawn tables ───────────────────────────────────────

(def MONSTER-DEFS
  {:baaz-draconian  @{:name "Baaz Draconian"  :hp 18 :hp-max 18 :ac 4  :thac0 18 :xp 65   :alive true}
   :kapak-draconian @{:name "Kapak Draconian" :hp 22 :hp-max 22 :ac 4  :thac0 17 :xp 120  :alive true}
   :bozak-draconian @{:name "Bozak Draconian" :hp 26 :hp-max 26 :ac 3  :thac0 16 :xp 270  :alive true}
   :sivak-draconian @{:name "Sivak Draconian" :hp 34 :hp-max 34 :ac 1  :thac0 15 :xp 650  :alive true}
   :aurak-draconian @{:name "Aurak Draconian" :hp 40 :hp-max 40 :ac 2  :thac0 14 :xp 975  :alive true}
   :blue-dragon     @{:name "Blue Dragon"     :hp 88 :hp-max 88 :ac -1 :thac0 10 :xp 7000 :alive true}
   :skeleton        @{:name "Skeleton"        :hp 12 :hp-max 12 :ac 7  :thac0 19 :xp 35   :alive true}
   :goblin          @{:name "Goblin"          :hp  8 :hp-max  8 :ac 6  :thac0 20 :xp 15   :alive true}
   :wolf            @{:name "Dark Wolf"       :hp 14 :hp-max 14 :ac 6  :thac0 19 :xp 25   :alive true}
   :sea-serpent     @{:name "Sea Serpent"     :hp 30 :hp-max 30 :ac 3  :thac0 15 :xp 500  :alive true}
   :red-dragon      @{:name "Red Dragon"      :hp 80 :hp-max 80 :ac 0  :thac0 11 :xp 6000 :alive true}})

(defn make-monster [kind]
  (merge @{} (MONSTER-DEFS kind)))

# Encounter tables per level — varied by region
(def ENCOUNTER-TABLE
  {0  [[:goblin :goblin]]                             # solace
   1  [[:goblin]]                                     # inn
   2  []                                              # tika (no encounters)
   3  [[:wolf :wolf] [:goblin :goblin :goblin]]        # darken wood
   4  [[:goblin :goblin] [:baaz-draconian]]            # que-shu
   5  []                                              # chieftain hut
   6  [[:skeleton :skeleton] [:goblin]]               # crystal cave
   7  [[:baaz-draconian :baaz-draconian] [:kapak-draconian :baaz-draconian]]  # xak tsaroth
   8  [[:bozak-draconian :sivak-draconian] [:kapak-draconian :kapak-draconian]] # xak dungeon
   9  []                                              # temple
   10 [[:wolf] [:goblin :goblin]]                     # qualinesti
   11 []                                              # palace
   12 [[:sea-serpent] [:skeleton :skeleton]]          # sea coast
   13 [[:sea-serpent :sea-serpent] [:skeleton]]       # newsea
   14 [[:baaz-draconian :baaz-draconian] [:kapak-draconian]] # tarsis
   15 []                                              # library
   16 [[:skeleton :skeleton :skeleton] [:sea-serpent]] # ergoth coast
   17 [[:sivak-draconian :bozak-draconian] [:aurak-draconian]] # pax tharkas
   18 [[:baaz-draconian :baaz-draconian :baaz-draconian]] # pax hall
   19 [[:red-dragon] [:aurak-draconian :sivak-draconian]]  # pax dungeon
   })

# ── Map accessors ──────────────────────────────────────────────

(defn tile-at [tiles x y]
  (tiles (+ (* y MAP-W) x)))

(defn set-tile! [tiles x y v]
  (put tiles (+ (* y MAP-W) x) v))

(defn passable? [tiles x y]
  (let [t (tile-at tiles x y)]
    (or (= t 0) (= t 2) (= t 3) (= t 4) (= t 5) (= t 6) (= t 7))))

# ── Direction helpers ──────────────────────────────────────────

(def DIR-DELTA {:north [0 -1] :south [0 1] :east [1 0] :west [-1 0]})
(def TURN-LEFT  {:north :west :west :south :south :east :east :north})
(def TURN-RIGHT {:north :east :east :south :south :west :west :north})

(defn facing-delta [dir] (DIR-DELTA dir))
(defn turn-left!  [player] (put player :dir (TURN-LEFT  (player :dir))))
(defn turn-right! [player] (put player :dir (TURN-RIGHT (player :dir))))

(defn- open-door-if-needed! [tiles x y]
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

# ── NPC lookup ─────────────────────────────────────────────────

(defn npc-at [entities x y]
  (find |(and (= ($ :x) x) (= ($ :y) y) ($ :dialog)) entities))

# ── Random encounter ───────────────────────────────────────────

(defn encounter-check? []
  (= 0 (% (math/floor (* (math/random) 32)) 32)))

(defn random-encounter [level]
  (let [table (or (ENCOUNTER-TABLE level) [])]
    (if (pos? (length table))
      (let [group (table (% (math/floor (* (math/random) (length table))) (length table)))]
        (map make-monster group))
      [])))

# ── World factory ──────────────────────────────────────────────

(defn- make-entities [npcs]
  (array/slice (map |(merge @{} $) npcs)))

(defn- level->world [level-num]
  (let [data (load-level level-num)
        [sx sy sdir] (data :spawn)]
    {:level    level-num
     :tiles    (array/slice (data :tiles))
     :entities (make-entities (data :npcs))
     :fog      (array/new-filled (* MAP-W MAP-H) true)
     :player   @{:x sx :y sy :dir sdir}}))

(defn make-world []
  (let [w (level->world 0)]
    (def mw @{})
    (eachp [k v] w (put mw k v))
    (put mw :player (w :player))
    mw))

(defn travel! [world dest-level arr-x arr-y arr-dir]
  "Travel to dest-level, placing the player at (arr-x, arr-y) facing arr-dir."
  (let [data (load-level dest-level)]
    (put world :level    dest-level)
    (put world :tiles    (array/slice (data :tiles)))
    (put world :entities (make-entities (data :npcs)))
    (put world :fog      (array/new-filled (* MAP-W MAP-H) true))
    (put (world :player) :x arr-x)
    (put (world :player) :y arr-y)
    (put (world :player) :dir arr-dir)))

(defn reveal-fog! [world]
  (let [px (get-in world [:player :x])
        py (get-in world [:player :y])]
    (for dy -1 2
      (for dx -1 2
        (let [fx (+ px dx) fy (+ py dy)]
          (when (and (>= fx 0) (< fx MAP-W) (>= fy 0) (< fy MAP-H))
            (put (world :fog) (+ (* fy MAP-W) fx) false)))))))
