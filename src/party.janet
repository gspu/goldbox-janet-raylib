# party.janet — party management, D&D stats, levelling
(import ./rng)

# ── Character templates (Heroes of the Lance) ─────────────────

(defn make-char [name race class str dex con int wis cha thac0 ac hp-max spells]
  @{:name      name
    :race      race
    :class     class
    :str       str   :dex dex   :con con
    :int       int   :wis wis   :cha cha
    :thac0     thac0
    :ac        ac
    :hp        hp-max
    :hp-max    hp-max
    :xp        0
    :level     3
    :alive     true
    :spells    spells
    :active    false})

# ── Accessors ─────────────────────────────────────────────────

(defn alive? [ch]    (ch :alive))
(defn dead?  [ch]    (not (ch :alive)))

(defn living-members [party]
  (filter alive? party))



# ── Damage & healing ──────────────────────────────────────────

(defn take-damage! [ch dmg]
  (put ch :hp (max 0 (- (ch :hp) dmg)))
  (when (<= (ch :hp) 0)
    (put ch :alive false)))

(defn heal! [ch amt]
  (when (alive? ch)
    (put ch :hp (min (ch :hp-max) (+ (ch :hp) amt)))))

(defn rest-party! [party]
  "Restore a portion of HP to all living members."
  (each ch (living-members party)
    (heal! ch (max 1 (math/floor (* (ch :hp-max) 0.5))))))

# ── Experience & levelling ────────────────────────────────────

(def XP-TABLE
  "XP thresholds for levels 1–10 (Fighter/Ranger baseline)."
  [0 2000 4000 8000 16000 32000 64000 125000 250000 500000])

(defn award-xp! [party xp]
  "Split XP equally among living party members."
  (let [live  (living-members party)
        share (if (pos? (length live)) (math/floor (/ xp (length live))) 0)]
    (each ch live
      (put ch :xp (+ (ch :xp) share))
      # Level up check
      (let [next-lv (+ (ch :level) 1)]
        (when (and (< next-lv (length XP-TABLE))
                   (>= (ch :xp) (XP-TABLE next-lv)))
          (put ch :level next-lv)
          (put ch :hp-max (+ (ch :hp-max) (rng/d6)))
          (put ch :hp     (ch :hp-max)))))))

# ── Stat modifier (3–18 → −3 to +3) ─────────────────────────

(defn stat-mod [stat]
  (cond
    (<= stat  3) -3
    (<= stat  5) -2
    (<= stat  8) -1
    (<= stat 12)  0
    (<= stat 15)  1
    (<= stat 17)  2
    3))

# ── Character creation ────────────────────────────────────────
# Available races and classes with their stat bonuses and spell lists.

(def RACES
  ["Human" "Half-Elf" "Elf" "Dwarf" "Kender" "Gnome"])

(def CLASSES
  ["Fighter" "Ranger" "Wizard" "Cleric" "Thief" "Paladin"])

# Racial stat bonuses: [str dex con int wis cha]
(def RACE-BONUSES
  {"Human"    [0  0  0  0  0  0]
   "Half-Elf" [0  1  0  1  0  1]
   "Elf"      [0  2 -1  1  0  1]
   "Dwarf"    [1  0  2 -1  0 -1]
   "Kender"   [-1 2  0  1  0  2]
   "Gnome"    [0  1  1  2  0 -1]})

# Class spell lists
(def CLASS-SPELLS
  {"Fighter"  []
   "Ranger"   []
   "Wizard"   ["Magic Missile" "Sleep" "Mirror Image"]
   "Cleric"   ["Cure Light Wounds" "Hold Person" "Bless"]
   "Thief"    []
   "Paladin"  ["Cure Light Wounds" "Bless"]})

# Class base THAC0 and AC
(def CLASS-BASE
  {"Fighter"  [18 6]
   "Ranger"   [17 5]
   "Wizard"   [19 5]
   "Cleric"   [18 4]
   "Thief"    [19 6]
   "Paladin"  [17 4]})

(defn roll-stats [race]
  "Roll 4d6-drop-lowest for each stat, then apply racial bonuses."
  (defn roll4d6 []
    (let [rolls [(rng/d6) (rng/d6) (rng/d6) (rng/d6)]
          total (reduce + 0 rolls)
          mn    (min ;rolls)]
      (- total mn)))
  (let [base  [(roll4d6) (roll4d6) (roll4d6) (roll4d6) (roll4d6) (roll4d6)]
        bonus (or (RACE-BONUSES race) [0 0 0 0 0 0])]
    (map (fn [b bns] (max 3 (min 18 (+ b bns)))) base bonus)))

(defn make-custom-char [name race class stats]
  "Build a character from creation choices."
  (let [[st dx cn it ws ch] stats
        [thac0 ac] (or (CLASS-BASE class) [18 6])
        hp-max (+ (rng/d8) (stat-mod cn))
        spells (or (CLASS-SPELLS class) [])]
    (make-char name race class st dx cn it ws ch thac0 ac (max 4 hp-max) spells)))

# Default hero templates — used as pre-filled names/races/classes in
# character creation. The player can overwrite any field; these are
# just a convenient starting point matching the Dragonlance heroes.
(def HERO-TEMPLATES
  [{:name "Tanis"      :race "Half-Elf" :race-idx 1 :class "Ranger" :class-idx 1}
   {:name "Raistlin"   :race "Human"    :race-idx 0 :class "Wizard" :class-idx 2}
   {:name "Goldmoon"   :race "Human"    :race-idx 0 :class "Cleric" :class-idx 3}
   {:name "Tasslehoff" :race "Kender"   :race-idx 4 :class "Thief"  :class-idx 4}])

(defn make-blank-creation []
  "Return creation slots pre-filled with the Dragonlance hero templates.
   The player can change name, race, class, or reroll stats freely."
  (def slots (array/new 4))
  (for i 0 4
    (def tpl (HERO-TEMPLATES i))
    (def race (tpl :race))
    (array/push slots
      @{:name      (tpl :name)
        :race-idx  (tpl :race-idx)
        :class-idx (tpl :class-idx)
        :stats     (roll-stats race)}))
  slots)
