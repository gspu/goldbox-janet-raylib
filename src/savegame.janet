# savegame.janet — save and load game state
#
# Save files: ~/.goldbox/slot<N>.dat  and  ~/.goldbox/slot<N>.meta
# The user-chosen name is stored inside the .meta file (first line).
# The filename is always slot<N> — stable and predictable.

(def NUM-SLOTS 10)

(defn- save-dir []
  "Save files go in ~/.goldbox_janet/"
  (let [home (os/getenv "HOME")]
    (string (or home ".") "/.goldbox_janet")))

(defn- slot-path [n]
  (string (save-dir) "/slot" n ".dat"))

(defn- meta-path [n]
  (string (save-dir) "/slot" n ".meta"))

(defn ensure-save-dir []
  (os/mkdir (save-dir)))

# ── Serialise helpers ─────────────────────────────────────────

(defn- serialise-char [ch]
  @{:name   (ch :name)   :race   (ch :race)   :class  (ch :class)
    :str     (ch :str)    :dex    (ch :dex)    :con    (ch :con)
    :int     (ch :int)    :wis    (ch :wis)    :cha    (ch :cha)
    :thac0   (ch :thac0)  :ac     (ch :ac)
    :hp      (ch :hp)     :hp-max (ch :hp-max)
    :xp      (ch :xp)     :level  (ch :level)
    :alive   (ch :alive)  :spells (ch :spells)
    :active  (ch :active)})

(defn- serialise-world [w]
  @{:level    (w :level)
    :tiles    (w :tiles)
    :fog      (w :fog)
    :player   @{:x   ((w :player) :x)
                :y   ((w :player) :y)
                :dir ((w :player) :dir)}
    :entities (w :entities)})

(defn- serialise-state [state]
  @{:mode       (state :mode)
    :active-idx (state :active-idx)
    :tick       (state :tick)
    :messages   (state :messages)
    :party      (map serialise-char (state :party))
    :world      (serialise-world (state :world))})

# ── Save ──────────────────────────────────────────────────────

(defn save! [state slot name]
  "Save to slot 0-9 with display name. Returns true on success."
  (ensure-save-dir)
  (try
    (let [data    (serialise-state state)
          buf     (marshal data)
          now     (os/date)
          ts      (string/format "%04d-%02d-%02d %02d:%02d"
                                 (+ 1900 (now :year))
                                 (+ 1    (now :month))
                                 (now :month-day)
                                 (now :hours)
                                 (now :minutes))
          display (if (and name (not= name "")) name (string "Slot " (+ slot 1)))
          # meta format: line1=display-name  line2=timestamp
          meta    (string display "\n" ts "\n")]
      (spit (slot-path slot) buf)
      (spit (meta-path slot) meta)
      true)
    ([err] (eprint "Save failed: " err) false)))

# ── Load ──────────────────────────────────────────────────────

(defn- restore-world [saved-w]
  @{:level    (saved-w :level)
    :tiles    (array/slice (saved-w :tiles))
    :fog      (array/slice (saved-w :fog))
    :entities (array/slice (saved-w :entities))
    :player   @{:x   (get-in saved-w [:player :x])
                :y   (get-in saved-w [:player :y])
                :dir (get-in saved-w [:player :dir])}})

(defn- restore-char [sc]
  @{:name   (sc :name)   :race   (sc :race)   :class  (sc :class)
    :str     (sc :str)    :dex    (sc :dex)    :con    (sc :con)
    :int     (sc :int)    :wis    (sc :wis)    :cha    (sc :cha)
    :thac0   (sc :thac0)  :ac     (sc :ac)
    :hp      (sc :hp)     :hp-max (sc :hp-max)
    :xp      (sc :xp)     :level  (sc :level)
    :alive   (sc :alive)  :spells (sc :spells)})

(defn load! [state slot]
  "Load from slot 0-9 into state. Returns true on success."
  (try
    (let [path (slot-path slot)
          data (when (os/stat path) (slurp path))]
      (if data
        (let [raw-data (unmarshal data)]
          (def loaded-party (array/slice (map restore-char (or (raw-data :party) @[]))))
          (put state :party      loaded-party)
          (put state :world      (restore-world (raw-data :world)))
          (put state :active-idx (or (raw-data :active-idx) 0))
          (put state :messages   (array/slice (or (raw-data :messages) @[])))
          (put state :combat     nil)
          (put state :dialog-npc nil)
          # If party is empty (save from before char-creation), go to charcreate
          (put state :mode
            (if (pos? (length loaded-party))
              (or (raw-data :mode) :explore)
              :charcreate))
          true)
        false))
    ([err] (eprint "Load failed: " err) false)))

# ── Delete ───────────────────────────────────────────────────

(defn delete! [slot]
  "Delete save slot. Returns true if something was deleted."
  (var deleted false)
  (let [dp (slot-path slot)
        mp (meta-path slot)]
    (when (os/stat dp) (os/rm dp) (set deleted true))
    (when (os/stat mp) (os/rm mp) (set deleted true)))
  deleted)

# ── Slot info ─────────────────────────────────────────────────

(defn slot-info [slot]
  "Return display string for a save slot."
  (let [mp (meta-path slot)]
    (if (os/stat mp)
      (let [lines (string/split "\n" (slurp mp))
            sname (or (get lines 0) "?")
            ts    (or (get lines 1) "")]
        (string/format "Slot %2d: %-24s  %s" (+ slot 1) sname ts))
      (string/format "Slot %2d: --- empty ---" (+ slot 1)))))
