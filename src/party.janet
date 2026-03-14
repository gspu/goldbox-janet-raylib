# party.janet — party management, D&D stats, levelling
(import ./rng)

# ── Character templates (Heroes of the Lance) ─────────────────

(defn- make-char [name race class str dex con int wis cha thac0 ac hp-max spells]
  @{:name   name
    :race   race
    :class  class
    :str    str   :dex dex   :con con
    :int    int   :wis wis   :cha cha
    :thac0  thac0
    :ac     ac
    :hp     hp-max
    :hp-max hp-max
    :xp     0
    :level  3
    :alive  true
    :spells spells          # list of spell names this character can cast
    :active false})

(defn make-party []
  [(make-char "Tanis"       "Half-Elf" "Ranger"  16 17 15 12 13 16
              17 5 24 [])
   (make-char "Raistlin"    "Human"    "Wizard"   9 17 10 18  8 11
              19 5 10 ["Magic Missile" "Sleep" "Mirror Image"])
   (make-char "Goldmoon"    "Human"    "Cleric"  14 14 16 12 18 16
              18 4 20 ["Cure Light Wounds" "Hold Person" "Bless"])
   (make-char "Tasslehoff"  "Kender"   "Thief"   11 19 13 15 10 17
              19 6 16 [])])

# ── Accessors ─────────────────────────────────────────────────

(defn alive? [ch]    (ch :alive))
(defn dead?  [ch]    (not (ch :alive)))
(defn hp     [ch]    (ch :hp))
(defn hp-max [ch]    (ch :hp-max))

(defn living-members [party]
  (filter alive? party))

(defn active-member [party]
  (or (find |($ :active) party)
      (first (living-members party))))

(defn set-active! [party idx]
  (each ch party (put ch :active false))
  (when (and (>= idx 0) (< idx (length party)))
    (let [ch (party idx)]
      (when (alive? ch)
        (put ch :active true)))))

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
