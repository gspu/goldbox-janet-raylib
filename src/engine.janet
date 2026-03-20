# engine.janet — input dispatch, mode state machine, message bus
#
# The engine owns the mutable game-state table and routes
# every keydown event to the correct handler for the current mode.

(import janet_raylib :as rl)
(import ./world)
(import ./party)
(import ./combat)
(import ./rng)
(import ./savegame)

# ── Message log ───────────────────────────────────────────────

(def MAX-MESSAGES 6)

(defn msg! [state text]
  (array/push (state :messages) text)
  (while (> (length (state :messages)) MAX-MESSAGES)
    (array/remove (state :messages) 0)))

# ── Initial game state ────────────────────────────────────────

(defn make-state []
  (let [w (world/make-world)
        p (party/make-party)]
    (world/reveal-fog! w)
    @{:mode        :explore
      :world       w
      :party       p
      :active-idx  0
      :combat      nil
      :dialog-npc  nil
      :messages    @["The War of the Lance has begun. Takhisis stirs."
                     "Your party stands in Solace. Move with arrow keys."]
      :tick        0
      :running     true
      :save-selected 0
      :save-naming    false
      :save-name-buf  ""}))

# ── Helpers ───────────────────────────────────────────────────

(defn- get-party [state] (state :party))

(defn active-char [state]
  ((get-party state) (state :active-idx)))

(defn- set-mode! [state m]
  (put state :mode m))

# ── Explore handlers ──────────────────────────────────────────

(defn- handle-explore [state key]
  (let [w      (state :world)
        tiles  (w :tiles)
        player (w :player)
        par    (state :party)]

    (cond
      # Movement
      (= key rl/SC_UP)
        (do
          (world/move-forward! tiles player)
          (world/reveal-fog! w)
          (msg! state "You move forward.")
          # Random encounter?
          (when (world/encounter-check?)
            (let [monsters (world/random-encounter (w :level))]
              (msg! state (string "You are attacked by " (length monsters) " enemies!"))
              (put state :combat (combat/make-combat par monsters))
              (set-mode! state :combat))))

      (= key rl/SC_DOWN)
        (do
          (world/move-backward! tiles player)
          (world/reveal-fog! w))

      (= key rl/SC_LEFT)
        (world/turn-left!  player)

      (= key rl/SC_RIGHT)
        (world/turn-right! player)

      # Talk
      (= key rl/SC_T)
        (let [[dx dy] (world/facing-delta (player :dir))
              nx (+ (player :x) dx)
              ny (+ (player :y) dy)
              npc (world/npc-at (w :entities) nx ny)]
          (if npc
            (do
              (put state :dialog-npc npc)
              (set-mode! state :dialog)
              (msg! state (string (npc :name) ": " (first (npc :dialog)))))
            (msg! state "There is no one to talk to.")))

      # Rest
      (= key rl/SC_C)
        (do
          (party/rest-party! par)
          (msg! state "The party rests and recovers HP."))

      # Inventory
      (= key rl/SC_I)
        (set-mode! state :inventory)

      # Interact — stairs, port, chest, or any transition tile.
      # Check the player's current tile first; if no connection found,
      # also check the tile they are facing (for doors that swung open
      # and became tile 3, or for stepping up to a door/stair).
      (= key rl/SC_RETURN)
        (let [t     (world/tile-at tiles (player :x) (player :y))
              # also check open-door tile (3) -> map to connection key 2
              t-key (if (= t 3) 2 t)
              [fdx fdy] (world/facing-delta (player :dir))
              fx    (+ (player :x) fdx)
              fy    (+ (player :y) fdy)
              ft    (if (and (>= fx 0) (< fx world/MAP-W)
                             (>= fy 0) (< fy world/MAP-H))
                      (world/tile-at tiles fx fy) 0)
              ft-key (if (= ft 3) 2 ft)
              dest  (or (world/get-connection (w :level) t-key)
                        (world/get-connection (w :level) ft-key))]
          (cond
            dest
              (let [[dest-level arr-x arr-y arr-dir] dest
                    level-names
                    {0  "Solace" 1  "the Inn of the Last Home"
                     2  "Tika's room" 3  "Darken Wood"
                     4  "Que-Shu" 5  "the Chieftain's Hut"
                     6  "the Crystal Cave" 7  "Xak Tsaroth"
                     8  "the depths of Xak Tsaroth" 9  "Mishakal's Temple"
                     10 "Qualinesti" 11 "the Speaker's Palace"
                     12 "the Sea of Blood Coast" 13 "the New Sea"
                     14 "Tarsis" 15 "the Library of Tarsis"
                     16 "the Ergoth Coast" 17 "Pax Tharkas"
                     18 "the Great Hall of Pax Tharkas"
                     19 "the Dungeons of Pax Tharkas"}
                    dest-name (or (level-names dest-level) (string "level " dest-level))]
                (world/travel! w dest-level arr-x arr-y arr-dir)
                (world/reveal-fog! w)
                (msg! state (string "You travel to " dest-name ".")))
            (= t 6)
              (do
                (world/set-tile! tiles (player :x) (player :y) 0)
                (let [gold (* 10 (+ 5 (rng/rand-int 20)))]
                  (msg! state (string "You find a chest with " gold " gold pieces!"))))
            (msg! state "Nothing to interact with here.")))

      # Save/Load menu
      (= key rl/SC_F10)
        (do (put state :save-selected 0)
            (set-mode! state :savemenu))

      # ESC in explore = quit game
      (= key rl/SC_ESCAPE)
        (put state :running false)

      # Party member select
      (= key rl/SC_F1) (put state :active-idx 0)
      (= key rl/SC_F2) (put state :active-idx 1)
      (= key rl/SC_F3) (put state :active-idx 2)
      (= key rl/SC_F4) (put state :active-idx 3))))

# ── Combat handlers ───────────────────────────────────────────

(defn- handle-combat [state key]
  (let [cs      (state :combat)
        par     (state :party)
        hero    ((state :party) (state :active-idx))
        targets (combat/living-monsters cs)]

    (when (combat/hero-turn? cs)
      (cond
        # Attack
        (or (= key rl/SC_A) (= key rl/SC_RETURN))
          (let [idx 0          # always target the first living monster
                phase (combat/hero-attack! cs hero idx)]
            (when (= phase :victory)
              (let [xp (combat/xp-reward cs)]
                (party/award-xp! par xp)
                (msg! state (string "Victory! Earned " xp " XP."))
                (put state :combat nil)
                (set-mode! state :explore)))
            (when (= phase :defeat)
              (msg! state "Your party has been slain...")
              (put state :running false)))

        # Cycle target (up/down arrow)
        (or (= key rl/SC_UP) (= key rl/SC_DOWN))
          nil  # future: cycle target index

        # Cast spell
        (= key rl/SC_S)
          (let [spells (hero :spells)]
            (if (pos? (length spells))
              (let [spell  (first spells)
                    target (if (pos? (length targets)) (first targets) hero)
                    phase  (combat/hero-cast-spell! cs hero spell target)]
                (msg! state (string (hero :name) " casts " spell "!"))
                (when (= phase :victory)
                  (let [xp (combat/xp-reward cs)]
                    (party/award-xp! par xp)
                    (msg! state (string "Victory! Earned " xp " XP."))
                    (put state :combat nil)
                    (set-mode! state :explore))))
              (msg! state (string (hero :name) " has no spells."))))

        # Flee
        (= key rl/SC_F)
          (let [phase (combat/hero-flee! cs)]
            (when (or (= phase :fled) (not= phase :active))
              (msg! state "The party escapes!")
              (put state :combat nil)
              (set-mode! state :explore)))))))

# ── Dialog handler ────────────────────────────────────────────

(defn- handle-dialog [state key]
  (when (or (= key rl/SC_RETURN) (= key rl/SC_ESCAPE) (= key rl/SC_T))
    (put state :dialog-npc nil)
    (set-mode! state :explore)))

# ── Inventory handler ─────────────────────────────────────────

(defn- handle-inventory [state key]
  (cond
    (or (= key rl/SC_I) (= key rl/SC_ESCAPE))
      (set-mode! state :explore)
    (= key rl/SC_F1) (put state :active-idx 0)
    (= key rl/SC_F2) (put state :active-idx 1)
    (= key rl/SC_F3) (put state :active-idx 2)
    (= key rl/SC_F4) (put state :active-idx 3)))

# ── Save/Load menu handler ────────────────────────────────────
# Key codes for printable characters used in name input.
# We accept A-Z (65-90), a-z (97-122), 0-9 (48-57), space (32), hyphen (45).

(defn- printable-char [key]
  "Map raylib KEY_* codes to printable characters for name input.
   Raylib letters are always KEY_A=65 .. KEY_Z=90 (uppercase codes only).
   Digits: KEY_ZERO=48 .. KEY_NINE=57.
   Special: KEY_SPACE=32  KEY_MINUS=45  KEY_APOSTROPHE=39
            KEY_PERIOD=46  KEY_SLASH=47  KEY_SEMICOLON=59
            KEY_EQUAL=61   KEY_LEFT_BRACKET=91  KEY_BACKSLASH=92
            KEY_RIGHT_BRACKET=93  KEY_GRAVE=96"
  (cond
    (and (>= key 65) (<= key 90))  (string/from-bytes (+ key 32))  # A-Z → a-z
    (and (>= key 48) (<= key 57))  (string/from-bytes key)          # 0-9
    (= key 32)   " "
    (= key 45)   "-"
    (= key 46)   "."
    (= key 95)   "_"   # KEY_KP_DECIMAL / underscore on some layouts
    (= key 39)   "'"
    nil))

(defn- handle-savemenu-naming [state key]
  "Handle key input while the user is typing a save name."
  (let [buf (or (state :save-name-buf) "")
        slot (state :save-selected)]
    (cond
      (= key rl/SC_ESCAPE)
        (do (put state :save-naming false)
            (put state :save-name-buf ""))

      (= key rl/SC_RETURN)
        (let [name (if (= buf "") (string "Save " (+ slot 1)) buf)]
          (if (savegame/save! state slot name)
            (do (msg! state (string "Saved: " name))
                (put state :save-naming false)
                (put state :save-name-buf "")
                (set-mode! state :explore))
            (do (put state :save-naming false)
                (msg! state "Save failed!"))))

      (= key rl/SC_BACKSPACE)
        (when (> (length buf) 0)
          (put state :save-name-buf (string/slice buf 0 (- (length buf) 1))))

      # Printable character
      (printable-char key)
        (when (< (length buf) 24)
          (put state :save-name-buf (string buf (printable-char key)))))))

(defn- handle-savemenu [state key]
  (if (state :save-naming)
    (handle-savemenu-naming state key)
    (let [slot (state :save-selected)]
      (cond
        (or (= key rl/SC_ESCAPE) (= key rl/SC_F10))
          (set-mode! state :explore)

        (= key rl/SC_UP)
          (put state :save-selected (% (+ slot savegame/NUM-SLOTS -1) savegame/NUM-SLOTS))

        (= key rl/SC_DOWN)
          (put state :save-selected (% (+ slot 1) savegame/NUM-SLOTS))

        # S = start name input, then save
        (= key rl/SC_S)
          (do (put state :save-naming true)
              (put state :save-name-buf ""))

        # L or Enter = load from selected slot
        (or (= key rl/SC_RETURN) (= key rl/SC_L))
          (if (savegame/load! state slot)
            (do (msg! state (string "Game loaded from slot " (+ slot 1) "."))
                (set-mode! state :explore))
            (msg! state (string "Slot " (+ slot 1) " is empty.")))

        # DEL = delete selected slot
        (= key rl/SC_DELETE)
          (if (savegame/delete! slot)
            (msg! state (string "Slot " (+ slot 1) " deleted."))
            (msg! state (string "Slot " (+ slot 1) " is already empty.")))))))

# ── Top-level event dispatcher ────────────────────────────────

(defn dispatch-key! [state key]
  "Route a keydown scancode to the correct mode handler."
  (case (state :mode)
    :explore   (handle-explore   state key)
    :combat    (handle-combat    state key)
    :dialog    (handle-dialog    state key)
    :inventory (handle-inventory state key)
    :savemenu  (handle-savemenu  state key)))

# ── Event loop step ───────────────────────────────────────────

(defn process-events! [state]
  "Drain all pending events from the raylib ring-buffer.
   Returns true while the game should keep running."
  (var running (state :running))
  (var ev (rl/poll-events))
  (while ev
    (let [t (ev :type)]
      (cond
        (= t :quit)    (do (put state :running false) (set running false))
        (= t :keydown) (dispatch-key! state (ev :key))))
    (set ev (rl/poll-events)))
  (put state :tick (+ (state :tick) 1))
  running)
